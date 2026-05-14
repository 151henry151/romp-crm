defmodule RompCrm.Reminders do
  @moduledoc """
  User reminders: ad-hoc rows in **`reminders`** (SMS-scheduled or future API) and optional
  **job schedule** SMS nudges driven by **`users.sms_reminder_prefs_json`**.

  Schedule nudges cover **jobs** with **`scheduled_on`** and **work items** with their own
  **`scheduled_on`** when it differs from the parent job’s date (so one SMS is not duplicated).
  """

  import Ecto.Query

  alias RompCrm.Repo
  alias RompCrm.Accounts.User
  alias RompCrm.Businesses
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobWorkItem
  alias RompCrm.Reminders.{JobReminderSendLog, Reminder}
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @default_prefs %{
    "job_offsets" => [1, 0],
    "timezone" => "America/New_York",
    "send_hour_local" => 9
  }

  @doc """
  Time zone options for the SMS reminder profile form (IANA IDs).
  """
  def profile_timezone_select_options do
    [
      {"Eastern (US & Canada)", "America/New_York"},
      {"Central (US & Canada)", "America/Chicago"},
      {"Mountain (US & Canada)", "America/Denver"},
      {"Arizona (no DST)", "America/Phoenix"},
      {"Pacific (US & Canada)", "America/Los_Angeles"},
      {"Alaska", "America/Anchorage"},
      {"Hawaii", "Pacific/Honolulu"},
      {"UTC", "Etc/UTC"}
    ]
  end

  @doc """
  Returns true if **`tz`** is one of **`profile_timezone_select_options/0`** values.
  """
  def valid_profile_timezone?(tz) when is_binary(tz) do
    tz in Enum.map(profile_timezone_select_options(), fn {_, id} -> id end)
  end

  def valid_profile_timezone?(_), do: false

  @doc """
  Returns true when **`utc_now`** falls in the same clock hour (0–23) as **`send_hour_local`**
  in **`decoded_prefs`** (`timezone`, `send_hour_local`). **`decoded_prefs`** must be the map
  returned by **`decode_prefs_json/1`** (or equivalent shape).
  """
  def local_send_hour_matches_now?(%DateTime{} = utc_now, prefs) when is_map(prefs) do
    tz = prefs |> Map.get("timezone", "America/New_York") |> to_string() |> String.trim()
    tz = if valid_profile_timezone?(tz), do: tz, else: "America/New_York"
    hour = parse_hour_0_23(Map.get(prefs, "send_hour_local"))

    case DateTime.shift_zone(utc_now, tz) do
      {:ok, local} ->
        local.hour == hour

      {:error, _} ->
        false
    end
  end

  @doc """
  Inserts a pending reminder for **`fire_at`** (UTC).
  """
  def create_reminder(attrs) when is_map(attrs) do
    %Reminder{}
    |> Reminder.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Pending **`reminders`** for **`user_id`** in any of **`business_ids`**, soonest **`fire_at`** first."
  def list_pending_reminders_for_user(user_id, business_ids)
      when is_integer(user_id) and is_list(business_ids) do
    ids = Enum.filter(business_ids, &is_integer/1)

    if ids == [] do
      []
    else
      Repo.all(
        from r in Reminder,
          where: r.user_id == ^user_id,
          where: r.business_id in ^ids,
          where: r.status == "pending",
          order_by: [asc: r.fire_at, asc: r.id]
      )
    end
  end

  @doc "Gets a reminder owned by **`user_id`** (any status), or **`nil`**."
  def get_user_reminder(id, user_id) when is_integer(id) and is_integer(user_id) do
    Repo.get_by(Reminder, id: id, user_id: user_id)
  end

  @doc "Updates **`body`**, **`fire_at`**, and optionally **`status`** for a user-owned row."
  def update_user_reminder(%Reminder{} = reminder, attrs) when is_map(attrs) do
    reminder
    |> Reminder.user_update_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a reminder row."
  def delete_user_reminder(%Reminder{} = reminder), do: Repo.delete(reminder)

  @doc """
  Combines a calendar **`date_s`** (`YYYY-MM-DD`) and optional clock **`time_s`** (`HH:MM`) in **`tz`**
  into a UTC **`DateTime`** (second precision). Blank **`time_s`** uses **`default_hour`**:00 in **`tz`**.
  """
  def compose_fire_at_utc(date_s, time_s, tz, default_hour \\ 9) do
    tz =
      tz
      |> to_string()
      |> String.trim()
      |> then(&if(valid_profile_timezone?(&1), do: &1, else: "America/New_York"))

    dh = parse_hour_0_23(default_hour)

    with {:ok, date} <- Date.from_iso8601(date_s |> to_string() |> String.trim()),
         %Time{} = t <- reminder_wall_time(time_s, dh),
         {:ok, ndt} <- NaiveDateTime.new(date, t),
         {:ok, local} <- datetime_from_naive_in_zone(ndt, tz) do
      utc = DateTime.shift_zone!(local, "Etc/UTC")
      {:ok, DateTime.truncate(utc, :second)}
    else
      _ -> :error
    end
  end

  defp reminder_wall_time(time_s, default_hour) do
    s = time_s |> to_string() |> String.trim()

    if s == "" do
      Time.new!(default_hour, 0, 0)
    else
      case parse_reminder_hhmm(s) do
        {:ok, t} -> t
        :error -> Time.new!(default_hour, 0, 0)
      end
    end
  end

  defp parse_reminder_hhmm(s) when is_binary(s) do
    case String.split(String.trim(s), ":") do
      [hs, ms | _] ->
        with {h, _} <- Integer.parse(String.trim(hs)),
             {m, _} <- Integer.parse(String.trim(ms)),
             {:ok, t} <- Time.new(h, m, 0) do
          {:ok, t}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp datetime_from_naive_in_zone(%NaiveDateTime{} = ndt, tz) do
    case DateTime.from_naive(ndt, tz) do
      {:ok, dt} ->
        {:ok, dt}

      {:ambiguous, dt, _} ->
        {:ok, dt}

      {:gap, _, _} ->
        :error
    end
  end

  @doc """
  Returns normalized reminder preferences from `users.sms_reminder_prefs_json`.

  Legacy JSON that only stored **`send_hour_utc`** is treated as **`Etc/UTC`** with that hour
  so existing schedules stay the same. New defaults use **Eastern (`America/New_York`)** and
  **9:00** local time.
  """
  def decode_prefs_json(nil), do: @default_prefs
  def decode_prefs_json(""), do: @default_prefs

  def decode_prefs_json(s) when is_binary(s) do
    case Jason.decode(String.trim(s)) do
      {:ok, %{} = raw} ->
        raw
        |> stringify_keys()
        |> coalesce_prefs_from_raw()
        |> finalize_prefs_map()

      _ ->
        @default_prefs
    end
  end

  defp stringify_keys(m) do
    Map.new(m, fn {k, v} -> {to_string(k), v} end)
  end

  defp coalesce_prefs_from_raw(raw) do
    cond do
      Map.has_key?(raw, "send_hour_local") ->
        Map.merge(@default_prefs, raw)

      Map.has_key?(raw, "send_hour_utc") ->
        h = parse_hour_0_23(Map.get(raw, "send_hour_utc"))

        @default_prefs
        |> Map.merge(Map.take(raw, ["job_offsets"]))
        |> Map.put("timezone", "Etc/UTC")
        |> Map.put("send_hour_local", h)

      true ->
        Map.merge(@default_prefs, Map.take(raw, ["job_offsets"]))
    end
  end

  defp finalize_prefs_map(prefs) do
    %{
      "job_offsets" => normalize_job_offsets_list(Map.get(prefs, "job_offsets")),
      "timezone" => normalize_profile_timezone(Map.get(prefs, "timezone")),
      "send_hour_local" => parse_hour_0_23(Map.get(prefs, "send_hour_local"))
    }
  end

  defp normalize_profile_timezone(tz) do
    tz = tz |> to_string() |> String.trim()
    if valid_profile_timezone?(tz), do: tz, else: "America/New_York"
  end

  defp normalize_job_offsets_list(raw) do
    list =
      (raw || [1, 0])
      |> List.wrap()
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
      |> Enum.filter(&(&1 in [0, 1, 2, 3, 7]))
      |> Enum.uniq()

    if list == [], do: [1, 0], else: Enum.sort(list, :desc)
  end

  defp parse_hour_0_23(v) when is_integer(v) and v >= 0 and v <= 23, do: v

  defp parse_hour_0_23(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} when n >= 0 and n <= 23 -> n
      _ -> 9
    end
  end

  defp parse_hour_0_23(_), do: 9

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
  (once per user/job/offset) when the current instant matches the user’s **local send hour**
  in their configured **IANA time zone**.
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
    today = DateTime.to_date(now)

    users =
      Repo.all(
        from u in User,
          where: u.sms_reminders_enabled == true,
          where: not is_nil(u.phone_normalized) and u.phone_normalized != ""
      )

    Enum.reduce(users, 0, fn user, acc ->
      prefs = decode_prefs_json(user.sms_reminder_prefs_json)

      if local_send_hour_matches_now?(now, prefs) do
        acc + send_job_nudges_for_user(user, prefs, today)
      else
        acc
      end
    end)
  end

  defp send_job_nudges_for_user(%User{} = user, prefs, %Date{} = today) do
    offsets = Map.get(prefs, "job_offsets") || [1, 0]

    businesses = Businesses.list_businesses_for_user(user)

    Enum.reduce(businesses, 0, fn biz, acc ->
      jobs = Jobs.list_upcoming_scheduled_jobs(biz.id, 120)

      n_jobs =
        Enum.reduce(jobs, 0, fn %Job{} = job, jacc ->
          jacc + try_send_job_offset(user, biz, job, offsets, today)
        end)

      pairs = Jobs.list_work_items_for_schedule_reminders(biz.id, 120)

      n_wis =
        Enum.reduce(pairs, 0, fn {%Job{} = job, %JobWorkItem{} = wi}, wacc ->
          wacc + try_send_work_item_offset(user, biz, job, wi, offsets, today)
        end)

      acc + n_jobs + n_wis
    end)
  end

  defp try_send_work_item_offset(user, biz, %Job{} = job, %JobWorkItem{} = wi, offsets, today) do
    Enum.reduce(offsets, 0, fn offset, acc ->
      case Date.diff(wi.scheduled_on, today) do
        ^offset ->
          kind = job_reminder_kind_for_work_item(offset, wi.id)

          if should_send_schedule_nudge?(user, job.id, kind, wi.scheduled_on) do
            case send_work_item_nudge_sms(user, biz, job, wi, offset, kind) do
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

  defp try_send_job_offset(user, biz, %Job{} = job, offsets, today) do
    Enum.reduce(offsets, 0, fn offset, acc ->
      case Date.diff(job.scheduled_on, today) do
        ^offset ->
          kind = job_reminder_kind(offset)

          if should_send_schedule_nudge?(user, job.id, kind, job.scheduled_on) do
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

  defp job_reminder_kind_for_work_item(offset, work_item_id)
       when is_integer(offset) and is_integer(work_item_id) do
    job_reminder_kind(offset) <> "_wi_" <> Integer.to_string(work_item_id)
  end

  defp should_send_schedule_nudge?(user, job_id, kind, %Date{} = anchor) do
    not log_exists?(user.id, job_id, kind, anchor)
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

        sched = Jobs.format_schedule_date_time(job.scheduled_on, job.scheduled_time)

        body =
          "Romp CRM: \"#{job.client_name}\" is scheduled #{when_txt} (#{sched}) — #{biz.name}."

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

  defp send_work_item_nudge_sms(user, biz, %Job{} = job, %JobWorkItem{} = wi, offset, kind) do
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

        sched = Jobs.format_schedule_date_time(wi.scheduled_on, wi.scheduled_time)

        title = String.slice(wi.title || "", 0, 120)

        body =
          "Romp CRM: work item \"#{title}\" (#{job.client_name}) is scheduled #{when_txt} (#{sched}) — #{biz.name}."

        case Messages.send_sms(to, body) do
          {:ok, _} ->
            log = %JobReminderSendLog{}

            _ =
              log
              |> JobReminderSendLog.changeset(%{
                user_id: user.id,
                job_id: job.id,
                kind: kind,
                anchor_on: wi.scheduled_on
              })
              |> Repo.insert()

            :sent

          {:error, _} ->
            :skipped
        end
    end
  end
end
