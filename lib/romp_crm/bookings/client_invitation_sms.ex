defmodule RompCrm.Bookings.ClientInvitationSms do
  @moduledoc """
  Composes the first outbound SMS a customer receives when a booking conversation
  starts (shared by production orchestrator and the scheduling-agent test sandbox).
  """

  alias RompCrm.Bookings.OpeningsPreview
  alias RompCrm.Businesses
  alias RompCrm.Repo
  alias RompCrm.Accounts.User
  alias RompCrm.Scheduling.{Playbook, Prefs}

  @doc """
  `link` is a map or struct with `job_type_label`, `duration_min_minutes`,
  `duration_max_minutes`, and `token` (optional — web link omitted when absent).
  """
  def compose(client_name, link, business_id, user_id) do
    business = Businesses.get_business!(business_id)
    prefs = technician_prefs(user_id)
    playbook = Playbook.snapshot_for_ai(business_id, user_id)

    first_name = client_name |> to_string() |> String.split(" ") |> List.first()
    duration_max = Map.get(link, :duration_max_minutes) || Map.get(link, "duration_max_minutes") || 120
    label = job_label(link)
    duration = duration_phrase(link)

    greeting =
      case playbook["greeting_template"] do
        t when is_binary(t) and t != "" ->
          t
          |> String.replace("{customer_first_name}", first_name || "there")
          |> String.replace("{customer_name}", client_name |> to_string())
          |> String.replace("{business_name}", business.name)

        _ ->
          if first_name in [nil, ""], do: "Hi,", else: "Hi #{first_name},"
      end

    openings =
      if prefs.customer_outreach_style == "ask" do
        ""
      else
        OpeningsPreview.phrase(business_id, user_id, duration_max)
      end

    link_bit =
      case booking_url(link) do
        nil -> ""
        url -> " Pick a time here: #{url} — or"
      end

    body_intro =
      if String.contains?(greeting, business.name) or String.contains?(greeting, "scheduling") do
        "#{greeting} I'm reaching out about your #{label} (typically #{duration})."
      else
        "#{greeting} this is the scheduling assistant for #{business.name} reaching out about " <>
          "your #{label} (typically #{duration})."
      end

    outreach_close =
      case prefs.customer_outreach_style do
        "offer" ->
          if openings != "" do
            "#{openings} Do any of those work for you?"
          else
            " What days and times work best for you?"
          end

        "ask" ->
          " What days and times usually work best for you?"

        _ ->
          if openings != "" do
            "#{openings}#{link_bit} just reply with your general availability and we'll work around your schedule."
          else
            "#{link_bit} just reply with your general availability and we'll work around your schedule."
          end
      end

    String.trim(body_intro <> outreach_close)
  end

  defp technician_prefs(user_id) do
    case Repo.get(User, user_id) do
      nil -> Prefs.default()
      %User{scheduling_prefs_json: json} -> Prefs.decode(json)
    end
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
