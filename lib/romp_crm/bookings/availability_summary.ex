defmodule RompCrm.Bookings.AvailabilitySummary do
  @moduledoc """
  Computes bookable slots and human-readable local-time offerings for SMS and AI
  context. All availability claims must come from this data — not workday prefs.
  """

  require Logger

  alias RompCrm.Repo
  alias RompCrm.Accounts.User
  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.AvailabilityEngine
  alias RompCrm.Scheduling.Prefs

  @default_days 14
  @default_max_slots 12
  @contractor_offer_count 4

  @type result :: %{
          open_slots: [%{String.t() => String.t()}],
          local_slot_offerings: [String.t()],
          contractor_phrase: String.t()
        }

  @doc """
  Returns UTC `open_slots`, local `local_slot_offerings`, and a short
  `contractor_phrase` for ask-before-text SMS.
  """
  def compute(business_id, user_id, duration_minutes, opts \\ [])
      when is_integer(business_id) and is_integer(user_id) do
    days = Keyword.get(opts, :days, @default_days)
    max_slots = Keyword.get(opts, :max_slots, @default_max_slots)
    prefs = technician_prefs(user_id)
    tz = prefs.timezone
    today = DateTime.utc_now() |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    to_date = Date.add(today, days - 1)

    slots =
      case Scheduling.combined_busy_blocks(business_id, user_id, {today, to_date}, tz) do
        {:ok, busy} ->
          busy
          |> AvailabilityEngine.available_slots(today, to_date, prefs, duration_minutes)
          |> Enum.reject(&(DateTime.compare(&1.start, DateTime.utc_now()) == :lt))
          |> apply_min_lead_days(prefs, tz)
          |> apply_scheduling_bias(prefs)
          |> Enum.take(max_slots)

        _ ->
          []
      end

    offerings = Enum.map(slots, &format_local_offering(&1.start, tz))

    %{
      open_slots:
        Enum.map(slots, fn slot ->
          %{
            "start" => DateTime.to_iso8601(slot.start),
            "end" => DateTime.to_iso8601(slot.end)
          }
        end),
      local_slot_offerings: offerings,
      contractor_phrase: contractor_phrase(offerings)
    }
  rescue
    e ->
      Logger.warning("AvailabilitySummary failed: #{Exception.message(e)}")

      %{open_slots: [], local_slot_offerings: [], contractor_phrase: ""}
  end

  @doc "Filters slot offerings for customer AI when contractor must approve first."
  def filter_offerings_for_link(summary, link_id, business_id, user_id)
      when is_map(summary) and is_integer(link_id) do
    alias RompCrm.Scheduling.{Playbook, SlotApprovals}

    if Playbook.confirm_before_offer_slots?(business_id, user_id) do
      approved = SlotApprovals.approved_offerings_for_link(link_id)

      if approved == [] do
        %{summary | local_slot_offerings: [], open_slots: [], contractor_phrase: ""}
      else
        keep = MapSet.new(approved)

        offerings =
          summary.local_slot_offerings
          |> Enum.filter(&MapSet.member?(keep, &1))

        open_slots =
          summary.open_slots
          |> Enum.take(length(offerings))

        %{
          summary
          | local_slot_offerings: offerings,
            open_slots: open_slots,
            contractor_phrase: contractor_phrase(offerings)
        }
      end
    else
      summary
    end
  end

  def filter_offerings_for_link(summary, _, _, _), do: summary

  @doc "Short phrase listing up to #{@contractor_offer_count} concrete local times."
  def contractor_phrase(offerings) when is_list(offerings) do
    case Enum.take(offerings, @contractor_offer_count) do
      [] -> ""
      times -> " We have openings at " <> format_time_list(times) <> "."
    end
  end

  defp apply_min_lead_days(slots, %Prefs{min_lead_days: 0}, _tz), do: slots

  defp apply_min_lead_days(slots, %Prefs{min_lead_days: days}, tz) when days > 0 do
    cutoff_date =
      DateTime.utc_now()
      |> DateTime.shift_zone!(tz)
      |> DateTime.to_date()
      |> Date.add(days)

    Enum.filter(slots, fn slot ->
      slot.start |> DateTime.shift_zone!(tz) |> DateTime.to_date()
      |> then(fn d -> Date.compare(d, cutoff_date) != :lt end)
    end)
  end

  defp apply_scheduling_bias(slots, %Prefs{scheduling_bias: "asap"}), do: slots

  defp apply_scheduling_bias(slots, %Prefs{scheduling_bias: "spread", timezone: tz}) do
    slots
    |> Enum.group_by(fn slot ->
      slot.start |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    end)
    |> Map.values()
    |> Enum.map(&List.first/1)
    |> Enum.sort_by(& &1.start, DateTime)
  end

  defp apply_scheduling_bias(slots, _), do: slots

  defp format_time_list([one]), do: one

  defp format_time_list([a, b]) do
    "#{a} or #{b}"
  end

  defp format_time_list(times) do
    {rest, [last]} = Enum.split(times, -1)
    Enum.join(rest, ", ") <> ", or " <> last
  end

  defp format_local_offering(%DateTime{} = utc, tz) do
    local = DateTime.shift_zone!(utc, tz)
    day = Calendar.strftime(local, "%a %b") <> " #{local.day}"
    hour = rem(local.hour, 12)
    hour = if hour == 0, do: 12, else: hour
    ampm = if local.hour < 12, do: "AM", else: "PM"
    mm = local.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day} at #{hour}:#{mm} #{ampm}"
  end

  defp technician_prefs(user_id) do
    case Repo.get(User, user_id) do
      %User{scheduling_prefs_json: json} when is_binary(json) -> Prefs.decode(json)
      _ -> Prefs.decode(nil)
    end
  end
end
