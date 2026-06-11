defmodule RompCrm.Scheduling.Setup do
  @moduledoc """
  First-time scheduling setup over SMS: structured questions, open-ended playbook
  capture, then replay of the held booking intent.
  """

  require Logger

  import Ecto.Query

  alias RompCrm.Accounts
  alias RompCrm.Accounts.User
  alias RompCrm.Ai.SchedulingPlaybookExtractor
  alias RompCrm.Bookings.Orchestrator
  alias RompCrm.Repo
  alias RompCrm.Scheduling.{Playbook, Prefs, SetupSession}
  alias RompCrm.SmsPendingBookingProposals

  @settings_url "https://rompcrm.com/romp-crm/users/settings"

  def needs_setup?(%User{} = user), do: Playbook.needs_setup?(user)

  def active_session?(business_id, phone_norm) when is_integer(business_id) do
    get_session(business_id, phone_norm) != nil
  end

  def get_session(business_id, phone_norm) do
    Repo.one(
      from s in SetupSession,
        where: s.business_id == ^business_id and s.phone_normalized == ^phone_norm
    )
  end

  @doc """
  Starts setup and returns the first SMS to send. `held_intent` is a map with
  `"type"` and payload to replay after setup completes.
  """
  def start!(business_id, user_id, phone_norm, held_intent) when is_map(held_intent) do
    Repo.delete_all(
      from s in SetupSession,
        where: s.business_id == ^business_id and s.phone_normalized == ^phone_norm
    )

    %SetupSession{}
    |> SetupSession.changeset(%{
      business_id: business_id,
      user_id: user_id,
      phone_normalized: phone_norm,
      phase: "awaiting_structured",
      held_intent_json: Jason.encode!(held_intent)
    })
    |> Repo.insert!()

    structured_intro(held_intent)
  end

  @doc "Handles an inbound contractor SMS while a setup session is active."
  def handle_message(%User{} = user, business_id, phone_norm, body) do
    case get_session(business_id, phone_norm) do
      nil ->
        :no_session

      %SetupSession{phase: "awaiting_structured"} = session ->
        handle_structured_reply(user, session, body)

      %SetupSession{phase: "awaiting_open_ended"} = session ->
        handle_open_ended_reply(user, session, body)
    end
  end

  defp handle_structured_reply(user, session, body) do
    case SchedulingPlaybookExtractor.extract_structured(body) do
      {:ok, extraction} ->
        structured =
          (Map.get(extraction, "structured") || %{})
          |> Map.put("prefs_updates", Map.get(extraction, "prefs_updates") || %{})

        session
        |> SetupSession.changeset(%{
          phase: "awaiting_open_ended",
          structured_answers_json: Jason.encode!(structured)
        })
        |> Repo.update!()

        prefs_bit = summarize_structured(structured)

        {:reply,
         "Got it#{prefs_bit}. Last thing — in your own words, how should I handle scheduling for you? " <>
           "Examples: how to greet customers, check with you before offering times, book far out vs ASAP, mornings vs afternoons. " <>
           "Reply skip to use defaults."}

      {:error, _} ->
        {:reply,
         "I didn't catch that — please reply with your work days/hours (e.g. Mon-Fri 8am-5pm) and A, B, or C for customer outreach: " <>
           "A) ask what works, B) offer specific times first, C) offer times but invite other options."}
    end
  end

  defp handle_open_ended_reply(user, session, body) do
    structured =
      case session.structured_answers_json do
        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, map} -> map
            _ -> %{}
          end

        _ ->
          %{}
      end

    open_text =
      if skip_open_ended?(body) do
        ""
      else
        String.trim(body)
      end

    extraction_input =
      Jason.encode!(%{
        "structured" => structured,
        "open_ended" => open_text
      })

    with {:ok, extraction} <- SchedulingPlaybookExtractor.extract(extraction_input),
         {:ok, user} <- Prefs.ensure_initialized(user),
         user <- Playbook.apply_extraction!(session.business_id, user.id, user, extraction),
         {:ok, user} <- Accounts.mark_scheduling_setup_completed(user),
         held <- decode_held_intent(session.held_intent_json),
         {:ok, replay_results} <- replay_held_intent(held, user, session) do
      Repo.delete!(session)

      summary =
        Map.get(extraction, "assistant_summary") ||
          Map.get(extraction, :assistant_summary) ||
          summarize_completion(structured, open_text)

      replay_line =
        case replay_results do
          [] -> ""
          results -> " " <> Enum.join(Enum.map(results, &replay_summary/1), " ")
        end

      {:completed, String.trim(summary <> replay_line)}
    else
      {:error, reason} ->
        Logger.warning("Scheduling setup completion failed: #{inspect(reason)}")
        {:reply, "Something went wrong saving your scheduling preferences. Try again or update Settings."}
    end
  end

  defp replay_held_intent(held, user, session) do
    business_id = session.business_id
    message_sid = "setup-replay-#{System.unique_integer([:positive])}"

    ctx = %{
      business_id: business_id,
      user_id: user.id,
      message_sid: message_sid,
      created_jobs: []
    }

    case held do
      %{"type" => "booking_initiate", "attrs" => attrs} ->
        Orchestrator.run_operations([{:booking_initiate, initiate_attrs(attrs)}], ctx)

      %{"type" => "pending_booking", "proposal" => proposal} ->
        phone_norm = session.phone_normalized

        SmsPendingBookingProposals.store!(
          business_id,
          user.id,
          phone_norm,
          proposal
        )

        {:ok, results} =
          SmsPendingBookingProposals.apply_pending(
            business_id,
            user.id,
            phone_norm,
            message_sid
          )

        {:ok, results}

      _ ->
        {:ok, []}
    end
  end

  defp structured_intro(held_intent) do
    customer = held_label(held_intent)

    "Before I text #{customer} — quick one-time scheduling setup (you can change this anytime in Settings).\n\n" <>
      "Link Google or Apple calendar in Romp CRM Settings when you can (#{@settings_url}) — I only see busy/free, not event details.\n\n" <>
      "1) What are your usual work days and hours? (e.g. Mon-Fri 8am-5pm)\n" <>
      "2) When I reach out to customers, should I (A) ask what works for them, (B) offer specific open times first, or (C) offer times but invite other options?\n\n" <>
      "Reply in one text."
  end

  defp held_label(%{"customer_name" => name}) when is_binary(name) and name != "", do: name
  defp held_label(%{"job_type_label" => job}) when is_binary(job) and job != "", do: "the customer about #{job}"
  defp held_label(_), do: "the customer"

  def held_intent_for_booking_initiate(attrs) when is_map(attrs) do
    %{
      "type" => "booking_initiate",
      "customer_name" => Map.get(attrs, :client_name) || Map.get(attrs, "client_name"),
      "job_type_label" => Map.get(attrs, :job_type_label) || Map.get(attrs, "job_type_label"),
      "attrs" => Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    }
  end

  def held_intent_for_pending_booking(proposal) when is_map(proposal) do
    %{
      "type" => "pending_booking",
      "customer_name" => proposal["client_name"] || proposal[:client_name],
      "job_type_label" => proposal["job_type_label"] || proposal[:job_type_label],
      "proposal" => Map.new(proposal, fn {k, v} -> {to_string(k), v} end)
    }
  end

  defp decode_held_intent(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp decode_held_intent(_), do: %{}

  defp skip_open_ended?(body) do
    t = body |> String.trim() |> String.downcase()
    t in ["skip", "no", "none", "default", "defaults", "n/a"]
  end

  defp summarize_structured(structured) when is_map(structured) do
    hours = Map.get(structured, "work_hours_summary") || Map.get(structured, "hours")
    style = Map.get(structured, "outreach_style_label") || Map.get(structured, "outreach_style")

    parts =
      []
      |> then(fn p -> if hours, do: p ++ ["#{hours}"], else: p end)
      |> then(fn p -> if style, do: p ++ ["outreach: #{style}"], else: p end)

    case parts do
      [] -> ""
      ps -> " — " <> Enum.join(ps, ", ")
    end
  end

  defp summarize_completion(structured, open_text) do
    base = "Scheduling setup saved" <> summarize_structured(structured) <> "."

    if open_text != "" do
      base <> " I'll follow your custom instructions."
    else
      base
    end
  end

  defp replay_summary({:booking_done, msg}), do: msg
  defp replay_summary(_), do: ""

  defp initiate_attrs(attrs) when is_map(attrs) do
    %{
      client_id: parse_optional_id(attrs["client_id"] || attrs[:client_id]),
      client_name: to_string(attrs["client_name"] || attrs[:client_name] || ""),
      phone: to_string(attrs["phone"] || attrs[:phone] || ""),
      job_id: parse_optional_id(attrs["job_id"] || attrs[:job_id]),
      job_type_label: to_string(attrs["job_type_label"] || attrs[:job_type_label] || ""),
      duration_min_minutes: parse_int(attrs["duration_min_minutes"] || attrs[:duration_min_minutes], 90),
      duration_max_minutes: parse_int(attrs["duration_max_minutes"] || attrs[:duration_max_minutes], 120)
    }
  end

  defp parse_optional_id(n) when is_integer(n) and n > 0, do: n

  defp parse_optional_id(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp parse_optional_id(_), do: nil

  defp parse_int(n, _) when is_integer(n), do: n

  defp parse_int(n, default) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
