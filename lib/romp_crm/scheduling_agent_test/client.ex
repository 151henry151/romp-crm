defmodule RompCrm.SchedulingAgentTest.Client do
  @moduledoc false

  require Logger

  alias RompCrm.Ai.CustomerBookingExtractor
  alias RompCrm.Bookings.AvailabilitySummary
  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.AvailabilityEngine
  alias RompCrm.Scheduling.Prefs
  alias RompCrm.SchedulingAgentTest.{Escalations, Notifications, Sandbox}

  @doc """
  Processes a test-customer message. Returns `{:ok, state, reply}` or `{:error, :no_active_link}`.
  """
  def process(state, user, business_id, body) when is_binary(body) do
    body = String.trim(body)

    case Sandbox.active_client_link(state) do
      nil ->
        {:error, :no_active_link}

      link ->
        state = Sandbox.append_client_turn(state, "client", body)
        prior = Sandbox.client_prior_turns(state) |> Enum.drop(-1)
        contexts = Sandbox.booking_contexts(state, business_id, user.id)

        case CustomerBookingExtractor.extract(body, contexts, prior) do
          {:ok, result} ->
            state = Sandbox.apply_job_updates(state, link, result.job_updates || %{})
            link = refreshed_link(state, link)

            {state, reply} = apply_result(state, link, result, user, business_id)
            state = Sandbox.append_client_turn(state, "scheduling_assistant", reply)
            {:ok, state, reply}

          {:error, reason} ->
            reply =
              "Sorry, we couldn't process that just now in the test workspace. (#{inspect(reason)})"

            state = Sandbox.append_client_turn(state, "scheduling_assistant", reply)
            {:ok, state, reply}
        end
    end
  end

  defp refreshed_link(state, link) do
    Enum.find(state["booking_links"] || [], &(&1["id"] == link["id"])) || link
  end

  defp apply_result(state, _link, %{action: nil} = result, _user, _bid) do
    reply = nonempty_reply(result.reply_sms) || "Thanks — we'll follow up shortly."
    {state, reply}
  end

  defp apply_result(state, link, %{action: %{type: :hard_booking} = action} = result, user, business_id) do
    duration_minutes = max(div(DateTime.diff(action.ends_at, action.starts_at, :second), 60), 1)
    window = %{start: action.starts_at, end: action.ends_at}

    case conflict_status(link, window, duration_minutes, user.id, business_id) do
      :available ->
        id = state["next_booking_id"]

        booking = %{
          "id" => id,
          "booking_link_id" => link["id"],
          "client_id" => link["client_id"],
          "job_id" => link["job_id"],
          "starts_at" => action.starts_at,
          "ends_at" => action.ends_at,
          "status" => "confirmed"
        }

        state =
          state
          |> Map.update!("bookings", &(&1 ++ [booking]))
          |> Map.put("next_booking_id", id + 1)
          |> Sandbox.mark_link_booked(link["id"])
          |> Sandbox.sync_job_from_booking(link["id"], action.starts_at, user.id)

        reply = nonempty_reply(result.reply_sms) || "You're all set — see you then!"

        state =
          notify_contractor_of_booking(state, link, booking, business_id, user.id)

        {state, reply}

      _ ->
        {state, unavailable_reply(state, link, user.id, business_id)}
    end
  end

  defp apply_result(state, link, %{action: %{type: :soft_availability} = action} = result, user, business_id) do
    id = state["next_request_id"]

    windows_json =
      action.windows
      |> Enum.map(fn w ->
        %{"start" => DateTime.to_iso8601(w.start), "end" => DateTime.to_iso8601(w.end)}
      end)
      |> Jason.encode!()

    request = %{
      "id" => id,
      "booking_link_id" => link["id"],
      "client_id" => link["client_id"],
      "availability_text" => action.availability_text,
      "parsed_windows_json" => windows_json,
      "job_type_label" => link["job_type_label"],
      "status" => "pending"
    }

    state =
      state
      |> Map.update!("booking_requests", &(&1 ++ [request]))
      |> Map.put("next_request_id", id + 1)

    reply = nonempty_reply(result.reply_sms) || "Got it — we'll confirm a time shortly."

    client_name = client_name(state, link)

    contractor_msg =
      Notifications.availability_received_message(link, action.availability_text, business_id, client_name)

    state = Sandbox.append_contractor_assistant(state, contractor_msg)
    {state, reply}
  end

  defp apply_result(state, link, %{action: %{type: :escalate_question, question_text: question}} = result, _user, _bid) do
    Escalations.escalate_from_client(state, link, question, result)
  end

  defp apply_result(state, _link, %{action: %{type: :cancel_booking, booking_id: booking_id}} = result, _user, _bid) do
    bookings =
      Enum.map(state["bookings"] || [], fn b ->
        if b["id"] == booking_id, do: Map.put(b, "status", "cancelled"), else: b
      end)

    state = Map.put(state, "bookings", bookings)
    reply = nonempty_reply(result.reply_sms) || "Your appointment has been cancelled."
    {state, reply}
  end

  defp apply_result(state, _link, %{action: _other} = result, _user, _bid) do
    reply = nonempty_reply(result.reply_sms) || "Thanks — we'll be in touch."
    {state, reply}
  end

  defp notify_contractor_of_booking(state, link, booking, business_id, user_id) do
    client_name = client_name(state, link)
    job = Sandbox.job_for_link(state, link)
    address = if(job, do: Sandbox.service_address_for_job(job), else: "")

    msg =
      Notifications.booking_confirmed_message(
        link,
        booking,
        business_id,
        user_id,
        client_name,
        address
      )

    Sandbox.append_contractor_assistant(state, msg)
  end

  defp client_name(state, link) do
    case Sandbox.client_for_link(state, link) do
      %{"client_name" => name} when is_binary(name) and name != "" -> name
      _ -> "A client"
    end
  end

  defp conflict_status(_link, window, duration_minutes, user_id, business_id) do
    prefs = technician_prefs(user_id)
    from_date = window.start |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()
    to_date = window.end |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()

    case Scheduling.combined_busy_blocks(business_id, user_id, {from_date, to_date}, prefs.timezone) do
      {:ok, busy} -> AvailabilityEngine.check_conflict(busy, window, duration_minutes)
      _ -> :conflict
    end
  end

  defp unavailable_reply(_state, link, user_id, business_id) do
    summary =
      AvailabilitySummary.compute(
        business_id,
        user_id,
        link["duration_max_minutes"] || 120
      )

    offerings = summary.local_slot_offerings

    if offerings != [] do
      "That time isn't available. Here are some openings: #{Enum.join(Enum.take(offerings, 4), ", ")}."
    else
      "That time isn't available — could you share a few other times that work?"
    end
  end

  defp technician_prefs(user_id) do
    case RompCrm.Repo.get(RompCrm.Accounts.User, user_id) do
      %RompCrm.Accounts.User{scheduling_prefs_json: json} when is_binary(json) ->
        Prefs.decode(json)

      _ ->
        Prefs.default()
    end
  end

  defp nonempty_reply(nil), do: nil
  defp nonempty_reply(""), do: nil
  defp nonempty_reply(s) when is_binary(s), do: String.trim(s)
end
