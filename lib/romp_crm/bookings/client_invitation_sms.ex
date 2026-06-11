defmodule RompCrm.Bookings.ClientInvitationSms do
  @moduledoc """
  Composes the first outbound SMS a customer receives when a booking conversation
  starts (shared by production orchestrator and the scheduling-agent test sandbox).
  """

  alias RompCrm.Bookings.OpeningsPreview
  alias RompCrm.Businesses

  @doc """
  `link` is a map or struct with `job_type_label`, `duration_min_minutes`,
  `duration_max_minutes`, and `token` (optional — web link omitted when absent).
  """
  def compose(client_name, link, business_id, user_id) do
    business = Businesses.get_business!(business_id)
    first_name = client_name |> to_string() |> String.split(" ") |> List.first()
    greeting = if first_name in [nil, ""], do: "Hi,", else: "Hi #{first_name},"

    duration_max = Map.get(link, :duration_max_minutes) || Map.get(link, "duration_max_minutes") || 120
    label = job_label(link)
    duration = duration_phrase(link)
    openings = OpeningsPreview.phrase(business_id, user_id, duration_max)

    link_bit =
      case booking_url(link) do
        nil -> ""
        url -> " Pick a time here: #{url} — or"
      end

    "#{greeting} this is the scheduling assistant for #{business.name} reaching out about " <>
      "your #{label} (typically #{duration}).#{openings}#{link_bit} just reply to this message " <>
      "with your general availability and we'll work around your schedule."
  end

  defp job_label(link) do
    case Map.get(link, :job_type_label) || Map.get(link, "job_type_label") do
      s when is_binary(s) and s != "" -> s
      _ -> "upcoming job"
    end
  end

  defp duration_phrase(link) do
    min = Map.get(link, :duration_min_minutes) || Map.get(link, "duration_min_minutes") || 60
    max = Map.get(link, :duration_max_minutes) || Map.get(link, "duration_max_minutes") || min

    cond do
      min == max -> format_hours(min / 60.0) <> " hour job"
      true -> "a #{format_hours(min / 60.0)}–#{format_hours(max / 60.0)} hour job"
    end
  end

  defp format_hours(hours) do
    if hours == Float.round(hours), do: "#{trunc(hours)}", else: "#{hours}"
  end

  defp booking_url(link) do
    token = Map.get(link, :token) || Map.get(link, "token")

    if is_binary(token) and token != "" do
      RompCrm.Bookings.Orchestrator.booking_url(token)
    end
  end
end
