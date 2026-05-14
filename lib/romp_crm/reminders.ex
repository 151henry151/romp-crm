defmodule RompCrm.Reminders do
  @moduledoc """
  User reminders: ad-hoc rows in **`reminders`** (SMS-scheduled or future API) and optional
  **job schedule** SMS nudges driven by **`users.sms_reminder_prefs_json`**.
  """

  import Ecto.Query

  alias RompCrm.Repo
  alias RompCrm.Accounts.User
  alias RompCrm.Businesses
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Reminders.{JobReminderSendLog, Reminder}
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @default_prefs %{"job_offsets" => [1, 0], "send_hour_utc" => 13}

  @doc """
  Inserts a pending reminder for **`fire_at`** (UTC).
  """
  def create_reminder(attrs) when is_map(attrs) do
    %Reminder{}
    |> Reminder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns merged reminder preferences (defaults plus decoded JSON from `users.sms_reminder_prefs_json`).
  """
  def decode_prefs_json(nil), do: @default_prefs
  def decode_prefs_json(""), do: @default_prefs

  def decode_prefs_json(s) when is_binary(s) do
    case Jason.decode(String.trim(s)) do
      {:ok, %{} = m} -> Map.merge(@default_prefs, stringify_keys(m))
      _ -> @default_prefs
    end
  end

  defp stringify_keys(m) do
    Map.new(m, fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Lists users who opted in and have a normalized phone on file (for outbound SMS).
  """
  def list_users_with_sms_reminders_enabled do
    Repo.all(
      from u in User,
        where: u.sms_reminders_enabled == true,
        where: not is_nil(u.phone_normalized) and u.phone_normalized != ""
    )
  end

  @doc """
  Delivers pending **`reminders`** whose **`fire_at`** is in the past, then sends job-date nudges
  (once per user/job/offset) when the current UTC hour matches prefs.
  """
  def run_scheduled_deliveries(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    limit = Keyword.get(opts, :reminder_row_limit, 50)

    n_rows = deliver_due_reminder_rows(now, limit)
    n_jobs = deliver_job_schedule_nudges(now)
    {:ok, %{reminder_rows: n_rows, job_nudges: n_jobs}}
  end

  defp deliver_due_reminder_rows(%DateTime{} = now, limit) when is_integer(limit) do
    due =
      Repo.all(
        from r in Reminder,
          where: r.status == "pending" and r.fire_at <= ^now,
          order_by: [asc: r.fire_at],
          limit: ^limit,
          preload: [:user]
      )

    Enum.count(due, fn r -> deliver_one_row_reminder(r) == :sent end)
  end

  defp deliver_one_row_reminder(%Reminder{user: %User{} = u} = r) do
    case Phone.to_e164(u.phone_normalized) do
      nil ->
        :skipped

      to ->
        prefix = "Romp CRM reminder:\n"
        body = prefix <> String.trim(r.body || "")

        case Messages.send_sms(to, body) do
          {:ok, _} ->
            _ = r |> Ecto.Changeset.change(status: "sent") |> Repo.update()
            :sent

          {:error, _} ->
            :skipped
        end
    end
  end

  defp deliver_job_schedule_nudges(%DateTime{} = now) do
    hour = now.hour
    today = DateTime.to_date(now)

    users =
      Repo.all(
        from u in User,
          where: u.sms_reminders_enabled == true,
          where: not is_nil(u.phone_normalized) and u.phone_normalized != ""
      )

    Enum.reduce(users, 0, fn user, acc ->
      prefs = decode_prefs_json(user.sms_reminder_prefs_json)
      send_hour = parse_send_hour_utc(Map.get(prefs, "send_hour_utc"))

      if hour != send_hour do
        acc
      else
        acc + send_job_nudges_for_user(user, prefs, today)
      end
    end)
  end

  defp parse_send_hour_utc(v) when is_integer(v) and v >= 0 and v <= 23, do: v

  defp parse_send_hour_utc(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} when n >= 0 and n <= 23 -> n
      _ -> 13
    end
  end

  defp parse_send_hour_utc(_), do: 13

  defp send_job_nudges_for_user(%User{} = user, prefs, %Date{} = today) do
    offsets = Map.get(prefs, "job_offsets") || [1, 0]
    offsets = if is_list(offsets), do: offsets, else: [1, 0]

    offsets =
      offsets
      |> Enum.flat_map(fn
        n when is_integer(n) -> [n]
        n when is_binary(n) ->
          case Integer.parse(String.trim(n)) do
            {i, _} -> [i]
            :error -> []
          end

        _ ->
          []
      end)
      |> Enum.uniq()

    offsets = if offsets == [], do: [1, 0], else: offsets

    businesses = Businesses.list_businesses_for_user(user)

    Enum.reduce(businesses, 0, fn biz, acc ->
      jobs = Jobs.list_upcoming_scheduled_jobs(biz.id, 120)

      sent_here =
        Enum.reduce(jobs, 0, fn %Job{} = job, jacc ->
          jacc + try_send_job_offset(user, biz, job, offsets, today)
        end)

      acc + sent_here
    end)
  end

  defp try_send_job_offset(user, biz, %Job{} = job, offsets, today) do
    Enum.reduce(offsets, 0, fn offset, acc ->
      case Date.diff(job.scheduled_on, today) do
        ^offset ->
          kind = job_reminder_kind(offset)

          if should_send_job_nudge?(user, job, kind, job.scheduled_on) do
            case send_job_nudge_sms(user, biz, job, offset) do
              :sent -> acc + 1
              _ -> acc
            end
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp job_reminder_kind(0), do: "day_of"
  defp job_reminder_kind(n) when is_integer(n) and n > 0, do: "before_#{n}"

  defp should_send_job_nudge?(user, job, kind, %Date{} = anchor) do
    not log_exists?(user.id, job.id, kind, anchor)
  end

  defp log_exists?(user_id, job_id, kind, %Date{} = anchor) do
    Repo.exists?(
      from l in JobReminderSendLog,
        where:
          l.user_id == ^user_id and l.job_id == ^job_id and l.kind == ^kind and l.anchor_on == ^anchor
    )
  end

  defp send_job_nudge_sms(user, biz, %Job{} = job, offset) do
    case Phone.to_e164(user.phone_normalized) do
      nil ->
        :skipped

      to ->
        when_txt =
          case offset do
            0 -> "today"
            1 -> "tomorrow"
            n -> "in #{n} days"
          end

        body =
          "Romp CRM: \"#{job.client_name}\" is scheduled #{when_txt} (#{Date.to_iso8601(job.scheduled_on)}) — #{biz.name}."

        case Messages.send_sms(to, body) do
          {:ok, _} ->
            log = %JobReminderSendLog{}
            kind = job_reminder_kind(offset)

            _ =
              log
              |> JobReminderSendLog.changeset(%{
                user_id: user.id,
                job_id: job.id,
                kind: kind,
                anchor_on: job.scheduled_on
              })
              |> Repo.insert()

            :sent

          {:error, _} ->
            :skipped
        end
    end
  end
end
