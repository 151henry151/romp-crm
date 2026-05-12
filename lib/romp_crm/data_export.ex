defmodule RompCrm.DataExport do
  @moduledoc false

  import Ecto.Query

  alias RompCrm.Accounts.User
  alias RompCrm.Accounts.UserNotifier
  alias RompCrm.Businesses
  alias RompCrm.DataExportSchedule
  alias RompCrm.Employees.{Employee, EmployeeTimeEntry}
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo
  alias RompCrm.SmsInteractionLogs
  alias RompCrm.TimeTracking.TimeEntry

  require Logger

  @doc """
  Users with an active schedule whose **`data_export_next_run_at`** is in the past (UTC).
  """
  def list_users_due_for_scheduled_export(%DateTime{} = now) do
    Repo.all(
      from u in User,
        where: u.data_export_schedule != "none",
        where: not is_nil(u.data_export_next_run_at),
        where: u.data_export_next_run_at <= ^now,
        select: u
    )
  end

  @doc """
  Builds CSV binaries and emails them. Only includes rows for businesses the user **owns**
  (`BusinessMembership` role **owner**).

  Returns **`{:ok, :sent}`**, **`{:ok, :skipped_no_owned_businesses}`**, or **`{:error, reason}`**.
  """
  def deliver_email_export(%User{} = user) do
    user = Repo.get!(User, user.id)
    owned = Businesses.list_owned_businesses_for_user(user)
    business_ids = Enum.map(owned, & &1.id)

    if business_ids == [] do
      case UserNotifier.deliver_data_export_no_owned_businesses(user) do
        {:ok, _} -> {:ok, :skipped_no_owned_businesses}
        {:error, _} = err -> err
      end
    else
      jobs_csv = build_jobs_csv(business_ids)
      employees_csv = build_employees_csv(business_ids)
      time_log_csv = build_time_log_csv(business_ids)
      sms_csv = build_sms_interactions_csv(business_ids)

      case UserNotifier.deliver_data_export_csvs(user, [
             {"jobs.csv", jobs_csv},
             {"employees.csv", employees_csv},
             {"time_log.csv", time_log_csv},
             {"sms_interactions.csv", sms_csv}
           ]) do
        {:ok, _} -> {:ok, :sent}
        {:error, _} = err -> err
      end
    end
  end

  @doc "Runs scheduled exports for users whose **`data_export_next_run_at`** has passed."
  def run_due_exports do
    now = DateTime.utc_now(:second)

    for user <- list_users_due_for_scheduled_export(now) do
      case deliver_email_export(user) do
        {:ok, _} ->
          case RompCrm.Accounts.advance_data_export_schedule_after_send(user) do
            {:ok, _} ->
              :ok

            {:error, cs} ->
              Logger.error(
                "DataExport: schedule update failed user_id=#{user.id} errors=#{inspect(cs.errors)}"
              )
          end

        {:error, reason} ->
          Logger.error("DataExport: email failed user_id=#{user.id} reason=#{inspect(reason)}")
      end
    end

    :ok
  end

  @doc "UTC **`DateTime`** for the next run after **`from`** (delegates to **`DataExportSchedule`**)."
  def compute_next_run_at(schedule, %DateTime{} = from) do
    DataExportSchedule.compute_next_run_at(schedule, from)
  end

  def build_jobs_csv(business_ids) do
    rows =
      if business_ids == [] do
        []
      else
        Repo.all(
          from j in Job,
            where: j.business_id in ^business_ids,
            order_by: [asc: j.business_id, asc: j.id]
        )
      end

    header = [
      "business_id",
      "job_id",
      "client_name",
      "address",
      "phone",
      "work_description",
      "priority",
      "status",
      "referred_by",
      "notes",
      "next_action",
      "inserted_at",
      "updated_at"
    ]

    lines =
      Enum.map(rows, fn j ->
        [
          j.business_id,
          j.id,
          j.client_name,
          j.address,
          j.phone,
          j.work_description,
          to_string(j.priority),
          to_string(j.status),
          j.referred_by,
          j.notes,
          j.next_action,
          format_dt(j.inserted_at),
          format_dt(j.updated_at)
        ]
        |> Enum.map(&csv_cell/1)
        |> Enum.join(",")
      end)

    Enum.join([Enum.map(header, &csv_cell/1) |> Enum.join(",") | lines], "\n") <> "\n"
  end

  def build_employees_csv(business_ids) do
    rows =
      if business_ids == [] do
        []
      else
        Repo.all(
          from e in Employee,
            where: e.business_id in ^business_ids,
            order_by: [asc: e.business_id, asc: e.id]
        )
      end

    header = ~w(business_id employee_id name title phone email notes inserted_at updated_at)

    lines =
      Enum.map(rows, fn e ->
        [
          e.business_id,
          e.id,
          e.name,
          e.title,
          e.phone,
          e.email,
          e.notes,
          format_dt(e.inserted_at),
          format_dt(e.updated_at)
        ]
        |> Enum.map(&csv_cell/1)
        |> Enum.join(",")
      end)

    Enum.join([Enum.join(Enum.map(header, &csv_cell/1), ",") | lines], "\n") <> "\n"
  end

  def build_time_log_csv(business_ids) do
    job_rows =
      if business_ids == [] do
        []
      else
        Repo.all(
          from t in TimeEntry,
            join: j in Job,
            on: j.id == t.job_id,
            where: t.business_id in ^business_ids,
            order_by: [asc: t.business_id, desc: t.started_at, desc: t.id],
            select: %{
              kind: type(^"job_time", :string),
              business_id: t.business_id,
              id: t.id,
              job_id: t.job_id,
              client_name: j.client_name,
              employee_id: nil,
              employee_name: nil,
              started_at: t.started_at,
              ended_at: t.ended_at,
              lunch_start: nil,
              lunch_end: nil,
              entry: t,
              notes: t.notes,
              inserted_at: t.inserted_at
            }
        )
        |> Enum.map(fn r ->
          dur = TimeEntry.format_duration(r.entry)
          Map.put(r, :duration, dur || "")
        end)
      end

    emp_rows =
      if business_ids == [] do
        []
      else
        Repo.all(
          from t in EmployeeTimeEntry,
            join: e in Employee,
            on: e.id == t.employee_id,
            where: t.business_id in ^business_ids,
            order_by: [asc: t.business_id, desc: t.clocked_in_at, desc: t.id],
            select: %{
              kind: type(^"employee_time", :string),
              business_id: t.business_id,
              id: t.id,
              job_id: nil,
              client_name: nil,
              employee_id: t.employee_id,
              employee_name: e.name,
              started_at: t.clocked_in_at,
              ended_at: t.clocked_out_at,
              lunch_start: t.lunch_start_at,
              lunch_end: t.lunch_end_at,
              entry: t,
              notes: t.notes,
              inserted_at: t.inserted_at
            }
        )
        |> Enum.map(fn r ->
          dur = EmployeeTimeEntry.format_duration(r.entry)
          Map.put(r, :duration, dur || "")
        end)
      end

    merged =
      (job_rows ++ emp_rows)
      |> Enum.sort_by(fn r ->
        ts =
          case r.started_at do
            %NaiveDateTime{} = ndt -> NaiveDateTime.to_iso8601(ndt)
            _ -> ""
          end

        {r.business_id, ts, r.id}
      end)

    header =
      ~w(entry_type business_id entry_id job_id client_name employee_id employee_name start end lunch_start lunch_end duration notes row_inserted_at)

    lines =
      Enum.map(merged, fn r ->
        [
          r.kind,
          r.business_id,
          r.id,
          r.job_id,
          r.client_name,
          r.employee_id,
          r.employee_name,
          format_naive(r.started_at),
          format_naive(r.ended_at),
          format_naive(r.lunch_start),
          format_naive(r.lunch_end),
          r.duration || "",
          r.notes,
          format_dt(r.inserted_at)
        ]
        |> Enum.map(&csv_cell/1)
        |> Enum.join(",")
      end)

    Enum.join([Enum.join(Enum.map(header, &csv_cell/1), ",") | lines], "\n") <> "\n"
  end

  def build_sms_interactions_csv(business_ids) do
    logs = SmsInteractionLogs.list_for_business_ids(business_ids)

    header =
      ~w(id inserted_at business_id user_id twilio_message_sid phone_normalized outcome inbound_body outbound_body planned_operations results_summary)

    lines =
      Enum.map(logs, fn l ->
        [
          l.id,
          format_dt(l.inserted_at),
          l.business_id,
          l.user_id,
          l.twilio_message_sid,
          l.phone_normalized,
          l.outcome,
          l.inbound_body,
          l.outbound_body,
          l.planned_operations,
          l.results_summary
        ]
        |> Enum.map(&csv_cell/1)
        |> Enum.join(",")
      end)

    Enum.join([Enum.join(Enum.map(header, &csv_cell/1), ",") | lines], "\n") <> "\n"
  end

  defp format_dt(nil), do: ""

  defp format_dt(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp format_naive(nil), do: ""

  defp format_naive(%NaiveDateTime{} = ndt) do
    NaiveDateTime.to_iso8601(ndt)
  end

  defp csv_cell(nil), do: ""

  defp csv_cell(v) when is_integer(v), do: to_string(v)

  defp csv_cell(v) when is_binary(v) do
    v = String.replace(v, "\r\n", "\n")
    v = String.replace(v, "\r", "\n")

    if String.contains?(v, [",", "\n", "\""]) do
      "\"" <> String.replace(v, "\"", "\"\"") <> "\""
    else
      v
    end
  end

  defp csv_cell(v), do: csv_cell(to_string(v))
end
