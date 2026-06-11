defmodule RompCrm.Bookings.CustomerBookingProcessor do
  @moduledoc """
  Handles inbound SMS from **clients** (non-user phone numbers) who have active
  booking conversations — the conversational half of customer self-scheduling.

  Shared-Twilio-number collision policy: when one client phone has active
  booking links with **multiple** businesses, the AI must resolve which business
  the message is for (`resolved_booking_link_id`). Until resolved, no scheduling
  action is applied and the exchange is recorded on **every** candidate thread;
  once resolved, only the resolved business's thread is written.
  """

  require Logger

  alias RompCrm.Accounts.User
  alias RompCrm.Ai.CustomerBookingExtractor
  alias RompCrm.Bookings
  alias RompCrm.Bookings.{AvailabilitySummary, BookingLink, EscalationCoordinator, Escalations, Intake, JobScheduleSync, Orchestrator}
  alias RompCrm.ClientChats
  alias RompCrm.Businesses
  alias RompCrm.Repo
  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.{AvailabilityEngine, Playbook, Prefs, SlotApprovals}
  alias RompCrm.SmsConversations
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @slot_preview_days 14
  @slot_preview_count 12

  @doc """
  Routes a Twilio inbound webhook payload from a client phone.

  Returns `{:ok, reply_text}` after sending the reply SMS, or `:ignore` when
  the phone has no active booking conversation (caller falls through to its
  unknown-number handling).
  """
  def deliver_from_twilio(params) when is_map(params) do
    body = (params["Body"] || "") |> to_string()
    from = (params["From"] || "") |> to_string()
    phone_norm = Phone.normalize_us(from)

    cond do
      phone_norm == "" ->
        :ignore

      true ->
        links = Bookings.active_links_for_client_phone(phone_norm)

        cond do
          links != [] ->
            process(phone_norm, body, links, params)

          ClientChats.taken_over_anywhere?(phone_norm) ->
            message_sid = (params["MessageSid"] || "") |> to_string()

            Logger.info(
              "Client booking inbound during human takeover (no pending link): sid=#{message_sid} phone=#{phone_norm}"
            )

            ClientChats.record_inbound_while_taken_over(phone_norm, body)
            {:ok, :human_takeover_silent}

          true ->
            :ignore
        end
    end
  end

  defp process(phone_norm, body, links, params) do
    message_sid = (params["MessageSid"] || "") |> to_string()

    Logger.info(
      "Client booking inbound: sid=#{message_sid} phone=#{phone_norm} candidate_links=#{length(links)}"
    )

    if human_takeover_active?(phone_norm) do
      ClientChats.record_inbound_while_taken_over(phone_norm, body)
      {:ok, :human_takeover_silent}
    else
      process_with_agent(phone_norm, body, links, params, message_sid)
    end
  end

  defp human_takeover_active?(phone_norm) do
    ClientChats.taken_over_anywhere?(phone_norm)
  end

  defp process_with_agent(phone_norm, body, links, params, message_sid) do
    contexts = Enum.map(links, &booking_context(&1, phone_norm))

    prior_turns =
      case links do
        [%BookingLink{business_id: bid}] ->
          SmsConversations.list_client_turns_for_ai(bid, phone_norm)

        _ ->
          []
      end

    case CustomerBookingExtractor.extract(body, contexts, prior_turns) do
      {:ok, result} ->
        resolved = resolve_link(result.resolved_booking_link_id, links)
        resolved = maybe_apply_job_updates(resolved, links, result.job_updates)
        {reply, recorded_links} = handle_result(result, resolved, links, phone_norm)

        record_exchange(recorded_links, phone_norm, body, reply)
        _ = Messages.send_sms(Phone.to_e164(phone_norm), reply)
        {:ok, reply}

      {:error, reason} ->
        Logger.warning(
          "Client booking extraction failed: sid=#{message_sid} phone=#{phone_norm} reason=#{inspect(reason)}"
        )

        reply =
          "Sorry, we couldn't process that just now. You can pick a time at your booking link, or try again in a few minutes."

        record_exchange(links, phone_norm, body, reply)
        _ = Messages.send_sms(Phone.to_e164(phone_norm), reply)
        {:ok, reply}
    end
  end

  # ── Resolution and action handling ──────────────────────────────────────────

  defp maybe_apply_job_updates(resolved, _links, job_updates)
       when job_updates in [nil, %{}] do
    resolved
  end

  defp maybe_apply_job_updates(resolved, links, job_updates) when is_map(job_updates) do
    target =
      resolved ||
        case links do
          [%BookingLink{} = only] -> only
          _ -> nil
        end

    case target do
      %BookingLink{} = link ->
        case Intake.apply_updates(link, job_updates) do
          {:ok, updated_link, _job} -> updated_link
          {:error, reason} ->
            Logger.warning("Client intake update failed: #{inspect(reason)}")
            link
        end

      _ ->
        resolved
    end
  end

  defp resolve_link(nil, [only_link]), do: only_link
  defp resolve_link(nil, _links), do: nil

  defp resolve_link(link_id, links) do
    Enum.find(links, &(&1.id == link_id)) ||
      case links do
        [only] -> only
        _ -> nil
      end
  end

  defp handle_result(%{action: nil} = result, resolved, links, _phone_norm) do
    reply = maybe_gate_slot_offer(result, resolved, nonempty_reply(result.reply_sms))
    {reply, if(resolved, do: [resolved], else: links)}
  end

  defp handle_result(%{action: %{type: :request_slot_approval} = action} = result, %BookingLink{} = link, _links, _phone_norm) do
    offerings = action.local_offerings || []
    full_summary = full_availability_summary(link)

    offerings =
      if offerings == [] do
        full_summary.local_slot_offerings |> Enum.take(3)
      else
        offerings
      end

    if offerings != [] do
      _ =
        SlotApprovals.request!(
          link,
          offerings,
          Enum.take(full_summary.open_slots, length(offerings)),
          result.reply_sms
        )

      reply =
        nonempty_reply(result.reply_sms) ||
          "Thanks — let me check with our team on available times and I'll get back to you shortly."

      {reply, [link]}
    else
      {nonempty_reply(result.reply_sms), [link]}
    end
  end

  defp handle_result(%{action: action} = _result, nil, links, _phone_norm) do
    # An action without a resolved conversation is only safe when unambiguous;
    # with multiple candidate businesses, ask the client to disambiguate.
    names =
      links
      |> Enum.map(&business_name(&1.business_id))
      |> Enum.uniq()

    Logger.info(
      "Client booking collision: action=#{inspect(action.type)} unresolved among #{inspect(names)}"
    )

    reply =
      "Just to be sure we schedule the right visit — you have booking requests open with " <>
        Enum.join(names, " and ") <> ". Which business is this time for?"

    {reply, links}
  end

  defp handle_result(%{action: %{type: :hard_booking} = action} = result, %BookingLink{} = link, _links, _phone_norm) do
    duration_minutes = max(div(DateTime.diff(action.ends_at, action.starts_at, :second), 60), 1)
    window = %{start: action.starts_at, end: action.ends_at}

    case conflict_status(link, window, duration_minutes) do
      :available ->
        case Bookings.create_booking(%{
               business_id: link.business_id,
               technician_user_id: link.technician_user_id,
               booking_link_id: link.id,
               client_id: link.client_id,
               job_id: link.job_id,
               starts_at: action.starts_at,
               ends_at: action.ends_at,
               status: "confirmed",
               confirmed_via: "sms"
             }) do
          {:ok, booking} ->
            _ = Bookings.mark_booking_link(link, "booked")
            _ = JobScheduleSync.sync_from_booking(booking)
            notify_technician_of_booking(link, booking)
            {nonempty_reply(result.reply_sms), [link]}

          {:error, changeset} ->
            Logger.warning("Client hard booking insert failed: #{inspect(changeset.errors)}")
            {unavailable_reply(link), [link]}
        end

      _conflict ->
        {unavailable_reply(link), [link]}
    end
  end

  defp handle_result(%{action: %{type: :soft_availability} = action} = result, %BookingLink{} = link, _links, _phone_norm) do
    windows_json =
      action.windows
      |> Enum.map(fn w ->
        %{"start" => DateTime.to_iso8601(w.start), "end" => DateTime.to_iso8601(w.end)}
      end)
      |> Jason.encode!()

    case Bookings.create_booking_request(%{
           business_id: link.business_id,
           technician_user_id: link.technician_user_id,
           booking_link_id: link.id,
           client_id: link.client_id,
           availability_text: action.availability_text,
           parsed_windows_json: windows_json,
           job_type_label: link.job_type_label,
           duration_min_minutes: link.duration_min_minutes,
           duration_max_minutes: link.duration_max_minutes,
           status: "pending"
         }) do
      {:ok, request} ->
        notify_technician_of_request(link, request)
        {nonempty_reply(result.reply_sms), [link]}

      {:error, changeset} ->
        Logger.warning("Client soft availability insert failed: #{inspect(changeset.errors)}")
        {"Got it — we'll be in touch shortly to set a time.", [link]}
    end
  end

  defp handle_result(%{action: %{type: :escalate_question, question_text: question}} = result, %BookingLink{} = link, _links, _phone_norm) do
    case EscalationCoordinator.escalate_from_client(link, %{
           question_text: question,
           client_reply: result.reply_sms
         }) do
      {:ok, _escalation, client_reply} ->
        {nonempty_reply(client_reply), [link]}

      {:error, reason} ->
        Logger.warning("Client booking escalation failed: #{inspect(reason)}")

        {nonempty_reply(result.reply_sms) ||
           "I don't have the answer to that, but I've reached out to our team and will get back to you soon.",
         [link]}
    end
  end

  defp handle_result(%{action: %{type: :cancel_booking, booking_id: booking_id}} = result, %BookingLink{} = link, _links, _phone_norm) do
    case Repo.get(RompCrm.Bookings.Booking, booking_id) do
      %{business_id: bid} = booking when bid == link.business_id ->
        _ = Bookings.cancel_booking(booking)
        notify_technician_of_cancellation(link, booking)
        {nonempty_reply(result.reply_sms), [link]}

      _ ->
        {nonempty_reply(result.reply_sms), [link]}
    end
  end

  # ── Context for the AI ──────────────────────────────────────────────────────

  defp booking_context(%BookingLink{} = link, _phone_norm) do
    link = Repo.preload(link, [:client, :technician_user])
    business = Businesses.get_business!(link.business_id)
    prefs = Prefs.decode(link.technician_user && link.technician_user.scheduling_prefs_json)

    summary =
      AvailabilitySummary.compute(
        link.business_id,
        link.technician_user_id,
        link.duration_max_minutes || 120,
        days: @slot_preview_days,
        max_slots: @slot_preview_count
      )
      |> AvailabilitySummary.filter_offerings_for_link(
        link.id,
        link.business_id,
        link.technician_user_id
      )

  playbook = Playbook.snapshot_for_ai(link.business_id, link.technician_user_id)

    %{
      "booking_link_id" => link.id,
      "business_name" => business.name,
      "client_name" => link.client && link.client.client_name,
      "job_type_label" => link.job_type_label,
      "duration_min_minutes" => link.duration_min_minutes,
      "duration_max_minutes" => link.duration_max_minutes,
      "timezone" => prefs.timezone,
      "booking_url" => Orchestrator.booking_url(link.token),
      "open_slots" => summary.open_slots,
      "local_slot_offerings" => summary.local_slot_offerings,
      "intake" => Intake.snapshot_for_link(link),
      "scheduling_memories" => Escalations.memories_snapshot_for_ai(link.business_id),
      "scheduling_playbook" => playbook,
      "confirm_before_offer_slots" => playbook["confirm_before_offer_slots"]
    }
  end

  defp full_availability_summary(%BookingLink{} = link) do
    AvailabilitySummary.compute(
      link.business_id,
      link.technician_user_id,
      link.duration_max_minutes || 120,
      days: @slot_preview_days,
      max_slots: @slot_preview_count
    )
  end

  defp maybe_gate_slot_offer(result, %BookingLink{} = link, reply) do
    if Playbook.confirm_before_offer_slots?(link.business_id, link.technician_user_id) and
         offers_specific_slots?(reply, link) do
      full = full_availability_summary(link)
      offerings = Enum.take(full.local_slot_offerings, 3)

      if offerings != [] do
        _ = SlotApprovals.request!(link, offerings, Enum.take(full.open_slots, 3), reply)

        "Thanks — let me check with our team on available times and I'll get back to you shortly."
      else
        reply
      end
    else
      reply
    end
  end

  defp maybe_gate_slot_offer(_result, _link, reply), do: reply

  defp offers_specific_slots?(reply, link) when is_binary(reply) do
    full = full_availability_summary(link)

    Enum.any?(full.local_slot_offerings, fn offering ->
      String.contains?(reply, offering)
    end)
  end

  defp offers_specific_slots?(_, _), do: false

  defp conflict_status(%BookingLink{} = link, window, duration_minutes) do
    prefs = technician_prefs(link)
    from_date = window.start |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()
    to_date = window.end |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()

    case Scheduling.combined_busy_blocks(
           link.business_id,
           link.technician_user_id,
           {from_date, to_date},
           prefs.timezone
         ) do
      {:ok, busy} -> AvailabilityEngine.check_conflict(busy, window, duration_minutes)
      _ -> :conflict
    end
  end

  defp technician_prefs(%BookingLink{} = link) do
    case Repo.get(User, link.technician_user_id) do
      nil -> Prefs.default()
      user -> Prefs.decode(user.scheduling_prefs_json)
    end
  end

  # ── Notifications and bookkeeping ──────────────────────────────────────────

  defp notify_technician_of_booking(link, booking) do
    notify_technician(link, fn business, client_name, tz ->
      address =
        case Bookings.service_address_for_link(link) do
          nil -> ""
          addr -> " Address: #{addr}."
        end

      "I reached out to #{client_name} and we've scheduled the #{link.job_type_label} for " <>
        format_window(booking.starts_at, booking.ends_at, tz) <>
        " (#{business.name}, booked by text).#{address}" <>
        " If that time doesn't work, reply here as soon as you can and I'll reach out to reschedule."
    end)
  end

  defp notify_technician_of_request(link, request) do
    notify_technician(link, fn business, client_name, _tz ->
      "#{client_name} sent availability for #{link.job_type_label}: \"#{request.availability_text}\". " <>
        "Confirm a time in Romp CRM or by replying here (#{business.name})."
    end)
  end

  defp notify_technician_of_cancellation(link, booking) do
    notify_technician(link, fn business, client_name, tz ->
      "#{client_name} cancelled the #{link.job_type_label} appointment " <>
        format_window(booking.starts_at, booking.ends_at, tz) <> " (#{business.name})."
    end)
  end

  defp notify_technician(%BookingLink{} = link, compose_fun) do
    link = Repo.preload(link, [:client, :technician_user])
    tech = link.technician_user

    with %User{} <- tech,
         e164 when is_binary(e164) <- Phone.to_e164(tech.phone_normalized || tech.phone) do
      business = Businesses.get_business!(link.business_id)
      client_name = (link.client && link.client.client_name) || "A client"
      tz = Prefs.decode(tech.scheduling_prefs_json).timezone

      _ = Messages.send_sms(e164, compose_fun.(business, client_name, tz))
      :ok
    else
      _ -> :ok
    end
  end

  defp record_exchange(links, phone_norm, inbound_body, reply) do
    links
    |> Enum.uniq_by(& &1.business_id)
    |> Enum.each(fn link ->
      _ =
        SmsConversations.record_client_message(
          link.business_id,
          link.technician_user_id,
          phone_norm,
          "inbound",
          inbound_body
        )

      _ =
        SmsConversations.record_client_message(
          link.business_id,
          link.technician_user_id,
          phone_norm,
          "outbound",
          reply
        )
    end)
  end

  defp business_name(business_id), do: Businesses.get_business!(business_id).name

  defp nonempty_reply(reply) do
    case String.trim(to_string(reply)) do
      "" -> "Got it — we'll follow up shortly."
      r -> r
    end
  end

  defp unavailable_reply(%BookingLink{} = link) do
    "Sorry — that time is no longer available. You can pick another open time here: " <>
      Orchestrator.booking_url(link.token) <> " or reply with another time that works."
  end

  defp format_window(starts_at, ends_at, tz) do
    local_start = DateTime.shift_zone!(starts_at, tz)
    local_end = DateTime.shift_zone!(ends_at, tz)

    Calendar.strftime(local_start, "%a %b %-d, %-I:%M %p") <>
      "–" <> Calendar.strftime(local_end, "%-I:%M %p")
  end
end
