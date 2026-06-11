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
  alias RompCrm.Bookings.{BookingLink, Orchestrator}
  alias RompCrm.Businesses
  alias RompCrm.Repo
  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.{AvailabilityEngine, Prefs}
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

    case phone_norm != "" && Bookings.active_links_for_client_phone(phone_norm) do
      links when is_list(links) and links != [] ->
        process(phone_norm, body, links, params)

      _ ->
        :ignore
    end
  end

  defp process(phone_norm, body, links, params) do
    message_sid = (params["MessageSid"] || "") |> to_string()

    Logger.info(
      "Client booking inbound: sid=#{message_sid} phone=#{phone_norm} candidate_links=#{length(links)}"
    )

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
    reply = nonempty_reply(result.reply_sms)
    {reply, if(resolved, do: [resolved], else: links)}
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

    %{
      "booking_link_id" => link.id,
      "business_name" => business.name,
      "client_name" => link.client && link.client.client_name,
      "job_type_label" => link.job_type_label,
      "duration_min_minutes" => link.duration_min_minutes,
      "duration_max_minutes" => link.duration_max_minutes,
      "timezone" => prefs.timezone,
      "booking_url" => Orchestrator.booking_url(link.token),
      "open_slots" => slot_preview(link, prefs)
    }
  end

  defp slot_preview(%BookingLink{} = link, %Prefs{} = prefs) do
    today = DateTime.utc_now() |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()
    to_date = Date.add(today, @slot_preview_days - 1)

    with {:ok, busy} <-
           Scheduling.combined_busy_blocks(
             link.business_id,
             link.technician_user_id,
             {today, to_date},
             prefs.timezone
           ) do
      busy
      |> AvailabilityEngine.available_slots(today, to_date, prefs, link.duration_max_minutes)
      |> Enum.take(@slot_preview_count)
      |> Enum.map(fn slot ->
        %{
          "start" => DateTime.to_iso8601(slot.start),
          "end" => DateTime.to_iso8601(slot.end)
        }
      end)
    else
      _ -> []
    end
  end

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
      "New booking: #{client_name} — #{link.job_type_label} — " <>
        format_window(booking.starts_at, booking.ends_at, tz) <>
        " (#{business.name}, booked by text)."
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
