defmodule RompCrm.SchedulingAgentTest.Notifications do
  @moduledoc false

  alias RompCrm.Businesses
  alias RompCrm.ContactInfo
  alias RompCrm.Scheduling.Prefs

  def client_question_message(client_name, phone_normalized, question_text) do
    phone_display = ContactInfo.format_display(phone_normalized)

    "#{client_name} just asked me: \"#{question_text}\" " <>
      "Do you want me to relay an answer to them, or would you prefer to reach out to them directly? " <>
      "Their number is #{phone_display}. (Test workspace — shown in your pane, not sent by SMS.)"
  end

  def booking_confirmed_message(link, booking, business_id, user_id, client_name, address \\ "") do
    business = Businesses.get_business!(business_id)
    tz = technician_timezone(user_id)
    address_bit = if address != "", do: " Address: #{address}.", else: ""

    "I reached out to #{client_name} and we've scheduled the #{link["job_type_label"]} for " <>
      format_window(booking["starts_at"], booking["ends_at"], tz) <>
      " (#{business.name}, booked by text).#{address_bit}" <>
      " If that time doesn't work, reply here as soon as you can and I'll reach out to reschedule. " <>
      "(Test workspace — shown in your pane, not sent by SMS.)"
  end

  def availability_received_message(link, availability_text, business_id, client_name) do
    business = Businesses.get_business!(business_id)

    "#{client_name} sent availability for #{link["job_type_label"]}: \"#{availability_text}\". " <>
      "Confirm a time in Romp CRM or by replying here (#{business.name}). " <>
      "(Test workspace — shown in your pane, not sent by SMS.)"
  end

  defp technician_timezone(user_id) do
    case RompCrm.Repo.get(RompCrm.Accounts.User, user_id) do
      %RompCrm.Accounts.User{scheduling_prefs_json: json} when is_binary(json) ->
        Prefs.decode(json).timezone

      _ ->
        Prefs.default().timezone
    end
  end

  defp format_window(starts_at, ends_at, tz) do
    local_start = DateTime.shift_zone!(starts_at, tz)
    local_end = DateTime.shift_zone!(ends_at, tz)

    Calendar.strftime(local_start, "%a %b %-d, %-I:%M %p") <>
      "–" <> Calendar.strftime(local_end, "%-I:%M %p")
  end
end
