defmodule RompCrm.DataExport do
  @moduledoc false

  import Ecto.Query

  alias RompCrm.Accounts.User
  alias RompCrm.Accounts.UserNotifier
  alias RompCrm.Businesses
  alias RompCrm.DataExportSchedule
  alias RompCrm.Employees.{Employee, EmployeeTimeEntry}
  alias RompCrm.Jobs.Job
  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Repo
  alias RompCrm.TimeTracking.TimeEntry

  require Logger

  @export_kind_strings ~w(jobs employees time_log audit_log)

  @doc "Ordered export kinds used for scheduled (full) exports and default selection."
  def all_export_kinds, do: [:jobs, :employees, :time_log, :audit_log]

  @doc """
  Parses **`params["export_kinds"]`** (from HTML **`export_kinds[]`** checkboxes) into a unique
  subset of allowed kinds. Returns **`{:ok, atoms_in_canonical_order}`** or **`{:error, :none_selected}`**.
  """
  def normalize_export_kinds(params) when is_map(params) do
    raw =
      case Map.get(params, "export_kinds") do
        nil -> []
        list when is_list(list) -> list
        one when is_binary(one) -> [one]
        _ -> []
      end

    allowed = MapSet.new(@export_kind_strings)

    chosen_set =
      raw
      |> Enum.map(&to_string/1)
      |> Enum.filter(&MapSet.member?(allowed, &1))
      |> MapSet.new()

    if MapSet.size(chosen_set) == 0 do
      {:error, :none_selected}
    else
      ordered =
        Enum.filter(all_export_kinds(), fn k ->
          MapSet.member?(chosen_set, Atom.to_string(k))
        end)

      {:ok, ordered}
    end
  end

  @doc """
  Parses **`params["export_business_ids"]`** (checkbox **`export_business_ids[]`**) into integer ids
  the user **owns**. Returns **`{:ok, sorted_unique_ids}`**, **`{:error, :no_owned_businesses}`**, or
  **`{:error, :no_business_selected}`** when the account owns workspaces but none were chosen (or
  only invalid ids were submitted).
  """
  def normalize_export_business_ids(%User{} = user, params) when is_map(params) do
    owned = Businesses.list_owned_businesses_for_user(user)
    allowed = MapSet.new(Enum.map(owned, & &1.id))

    if MapSet.size(allowed) == 0 do
      {:error, :no_owned_businesses}
    else
      raw =
        case Map.get(params, "export_business_ids") do
          nil -> []
          list when is_list(list) -> list
          one when is_binary(one) -> [one]
          _ -> []
        end

      chosen =
        raw
        |> Enum.flat_map(fn
          v when is_integer(v) ->
            if MapSet.member?(allowed, v), do: [v], else: []

          v when is_binary(v) ->
            case Integer.parse(String.trim(to_string(v))) do
              {i, _} -> if MapSet.member?(allowed, i), do: [i], else: []
              :error -> []
            end

          _ ->
            []
        end)
        |> MapSet.new()
        |> MapSet.to_list()
        |> Enum.sort()

      if chosen == [] do
        {:error, :no_business_selected}
      else
        {:ok, chosen}
      end
    end
  end

  @doc false
  def build_export_files(business_ids, kinds) when is_list(business_ids) and is_list(kinds) do
    for kind <- kinds, reduce: [] do
      acc ->
        {name, body} = file_for_kind(business_ids, kind)
        [{name, body} | acc]
    end
    |> Enum.reverse()
  end

  defp file_for_kind(business_ids, :jobs), do: {"jobs.csv", build_jobs_csv(business_ids)}
  defp file_for_kind(business_ids, :employees), do: {"employees.csv", build_employees_csv(business_ids)}
  defp file_for_kind(business_ids, :time_log), do: {"time_log.csv", build_time_log_csv(business_ids)}
  defp file_for_kind(business_ids, :audit_log), do: {"audit_log.csv", build_audit_log_csv(business_ids)}

  @doc """
  Builds a response body for a browser download: one CSV, or a ZIP when multiple files are selected.
  """
  def build_download_payload(files) when is_list(files) do
    case files do
      [] ->
        {:error, :empty}

      [{name, body}] ->
        {:ok, {:one, name, body}}

      many ->
        tmp = Path.join(System.tmp_dir!(), "romp-crm-export-#{System.unique_integer([:positive])}.zip")
        cl_tmp = String.to_charlist(tmp)

        file_specs =
          Enum.map(many, fn {fname, body} ->
            {String.to_charlist(fname), body}
          end)

        try do
          case :zip.create(cl_tmp, file_specs, []) do
            {:ok, _} ->
              data = File.read!(tmp)
              {:ok, {:zip, data}}

            {:error, reason} ->
              {:error, {:zip_failed, reason}}
          end
        after
          _ = File.rm(tmp)
        end
    end
  end

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

  Same as **`deliver_email_export(user, all_export_kinds(), all_owned_business_ids)`** — used by
  scheduled exports (full kinds, all owned workspaces).
  """
  def deliver_email_export(%User{} = user) do
    user = Repo.get!(User, user.id)
    owned = Businesses.list_owned_businesses_for_user(user)
    business_ids = Enum.map(owned, & &1.id)
    do_deliver_email_export(user, all_export_kinds(), business_ids)
  end

  @doc """
  Emails CSV attachments for **`kinds`** limited to **`business_ids`** (each must be a business the
  user owns; callers should use **`normalize_export_business_ids/2`**).

  Returns **`{:ok, :sent}`**, **`{:ok, :skipped_no_owned_businesses}`**, or **`{:error, reason}`**.
  """
  def deliver_email_export(%User{} = user, kinds, business_ids)
      when is_list(kinds) and is_list(business_ids) do
    user = Repo.get!(User, user.id)
    do_deliver_email_export(user, kinds, business_ids)
  end

  defp do_deliver_email_export(user, kinds, business_ids) do
    if business_ids == [] do
      case UserNotifier.deliver_data_export_no_owned_businesses(user) do
        {:ok, _} -> {:ok, :skipped_no_owned_businesses}
        {:error, _} = err -> err
      end
    else
      files = build_export_files(business_ids, kinds)

      case UserNotifier.deliver_data_export_csvs(user, files) do
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

    header = ~w(business_id employee_id user_id name title phone email notes can_edit_jobs can_log_job_time can_log_own_employee_time can_log_employee_time_for_others inserted_at updated_at)

    lines =
      Enum.map(rows, fn e ->
        [
          e.business_id,
          e.id,
          e.user_id,
          e.name,
          e.title,
          e.phone,
          e.email,
          e.notes,
          e.can_edit_jobs,
          e.can_log_job_time,
          e.can_log_own_employee_time,
          e.can_log_employee_time_for_others,
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

    header = ~w(entry_type business_id entry_id job_id client_name employee_id employee_name start end lunch_start lunch_end duration notes row_inserted_at)

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

  def build_audit_log_csv(business_ids) do
    logs = BusinessAuditLogs.list_for_business_ids(business_ids)

    header = ~w(id inserted_at business_id actor_user_id actor_email source action entity_type entity_id metadata)

    lines =
      Enum.map(logs, fn l ->
        actor_email =
          case l.actor_user do
            %{email: e} when is_binary(e) -> e
            _ -> ""
          end

        [
          l.id,
          format_dt(l.inserted_at),
          l.business_id,
          l.actor_user_id,
          actor_email,
          l.source,
          l.action,
          l.entity_type,
          l.entity_id,
          l.metadata
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
