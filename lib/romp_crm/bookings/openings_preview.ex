defmodule RompCrm.Bookings.OpeningsPreview do
  @moduledoc """
  Short human-readable preview of upcoming scheduling openings for contractor SMS.
  """

  require Logger

  alias RompCrm.Repo
  alias RompCrm.Accounts.User
  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.AvailabilityEngine
  alias RompCrm.Scheduling.Prefs

  @preview_days 7

  @doc """
  Returns a phrase like `" We have openings Tuesday afternoon or Wednesday morning."`
  or `""` when none are available. `duration_minutes` sizes each slot (default 120).
  """
  def phrase(business_id, user_id, duration_minutes \\ 120)
      when is_integer(business_id) and is_integer(user_id) do
    tz = technician_timezone(user_id)
    today = DateTime.utc_now() |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    prefs = technician_prefs(user_id)
    to_date = Date.add(today, @preview_days - 1)

    {:ok, busy} =
      Scheduling.combined_busy_blocks(business_id, user_id, {today, to_date}, tz)

    busy
    |> AvailabilityEngine.available_slots(today, to_date, prefs, duration_minutes)
    |> Enum.reject(&(DateTime.compare(&1.start, DateTime.utc_now()) == :lt))
    |> Enum.map(fn slot ->
      local = DateTime.shift_zone!(slot.start, tz)
      {Calendar.strftime(local, "%A"), day_period(local.hour)}
    end)
    |> Enum.uniq()
    |> Enum.take(2)
    |> case do
      [] -> ""
      pairs -> " We have openings " <> Enum.map_join(pairs, " or ", fn {day, period} -> "#{day} #{period}" end) <> "."
    end
  rescue
    e ->
      Logger.warning("OpeningsPreview failed: #{Exception.message(e)}")
      ""
  end

  defp technician_timezone(user_id) do
    case Repo.get(User, user_id) do
      %User{sms_reminder_prefs_json: json} when is_binary(json) ->
        json
        |> RompCrm.Reminders.decode_prefs_json()
        |> Map.get("timezone", "America/New_York")

      _ ->
        "America/New_York"
    end
  end

  defp technician_prefs(user_id) do
    case Repo.get(User, user_id) do
      %User{scheduling_prefs_json: json} when is_binary(json) -> Prefs.decode(json)
      _ -> Prefs.default()
    end
  end

  defp day_period(hour) when hour < 12, do: "morning"
  defp day_period(hour) when hour < 17, do: "afternoon"
  defp day_period(_), do: "evening"
end
