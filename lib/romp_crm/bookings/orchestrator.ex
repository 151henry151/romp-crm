defmodule RompCrm.Bookings.Orchestrator do
  @moduledoc """
  Executes technician-initiated booking operations parsed from agent messages
  (`RompCrm.Ai.SmsBookingExtractor` ops): starts client booking conversations,
  edits duration estimates, confirms soft availability, and cancels bookings.

  Each operation returns `{:ok, summary}` or `{:skipped, reason}`; the caller
  folds summaries into the assistant reply.
  """

  require Logger

  alias RompCrm.Bookings
  alias RompCrm.Bookings.ClientInvitationSms
  alias RompCrm.Businesses
  alias RompCrm.Clients
  alias RompCrm.SmsConversations
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @doc """
  Runs booking ops with `ctx` = `%{business_id, user_id, message_sid}`.
  `ctx` may also carry `:created_jobs` — `%Job{}` rows created earlier in the
  same inbound message — so an "add the lead and schedule with her" text links
  the booking to the just-created job/client instead of duplicating them.
  Always returns `{:ok, results}` (failures surface per-op as `{:skipped, reason}`).
  """
  def run_operations(ops, ctx) when is_list(ops) and is_map(ctx) do
    {:ok, Enum.map(ops, &apply_op(&1, ctx))}
  end

  defp apply_op({:booking_initiate, attrs}, ctx) do
    phone_norm = Phone.normalize_us(attrs.phone)
    e164 = Phone.to_e164(phone_norm)

    cond do
      is_nil(e164) ->
        Logger.info(
          "Booking initiate skipped: sid=#{ctx.message_sid} business_id=#{ctx.business_id} reason=:invalid_phone phone=#{inspect(attrs.phone)}"
        )

        {:skipped, :invalid_phone}

      true ->
        matched_job = match_created_job(ctx, attrs, phone_norm)
        job_id = attrs.job_id || (matched_job && matched_job.id)

        with {:ok, client} <- resolve_client(attrs, phone_norm, matched_job, ctx),
             {:ok, link} <-
               Bookings.create_booking_link(%{
                 business_id: ctx.business_id,
                 technician_user_id: ctx.user_id,
                 client_id: client.id,
                 job_id: job_id,
                 job_type_label: attrs.job_type_label,
                 duration_min_minutes: attrs.duration_min_minutes,
                 duration_max_minutes: attrs.duration_max_minutes,
                 client_phone_normalized: phone_norm
               }) do
          first_sms = ClientInvitationSms.compose(client.client_name, link, ctx.business_id, ctx.user_id)
          deliver_client_sms(e164, first_sms, phone_norm, ctx)

          {:booking_done,
           "Sent #{display_name(client, attrs)} a booking text for the #{label_or_job(link)} (#{duration_phrase(link)}) with link #{booking_url(link.token)}."}
        else
          {:error, reason} ->
            Logger.warning(
              "Booking initiate failed: sid=#{ctx.message_sid} business_id=#{ctx.business_id} reason=#{inspect(reason)}"
            )

            {:skipped, :initiate_failed}
        end
    end
  end

  defp apply_op({:booking_update_duration, link_id, min_minutes, max_minutes}, ctx) do
    case scoped_link(link_id, ctx.business_id) do
      nil ->
        {:skipped, :not_found}

      link ->
        case Bookings.update_link_duration(link, min_minutes, max_minutes) do
          {:ok, updated} ->
            {:booking_done, "Updated the #{label_or_job(updated)} estimate to #{duration_phrase(updated)}."}

          {:error, _} ->
            {:skipped, :update_failed}
        end
    end
  end

  defp apply_op({:booking_confirm_soft, request_id, starts_at, ends_at}, ctx) do
    request = safe_get_request(request_id, ctx.business_id)

    cond do
      is_nil(request) ->
        {:skipped, :not_found}

      request.status != "pending" ->
        {:skipped, :not_pending}

      true ->
        case Bookings.confirm_booking_request(request, %{
               starts_at: starts_at,
               ends_at: ends_at,
               confirmed_via: "technician"
             }) do
          {:ok, booking} ->
            notify_client_of_confirmation(request, booking, ctx)
            {:booking_done, "Booking confirmed for #{format_window(booking.starts_at, booking.ends_at, ctx)}."}

          {:error, _} ->
            {:skipped, :confirm_failed}
        end
    end
  end

  defp apply_op({:booking_cancel, booking_id, reason}, ctx) do
    case safe_get_booking(booking_id, ctx.business_id) do
      nil ->
        {:skipped, :not_found}

      booking ->
        case Bookings.cancel_booking(booking) do
          {:ok, _} ->
            notify_client_of_cancellation(booking, reason, ctx)
            {:booking_done, "Cancelled the booking#{if reason, do: " (#{reason})", else: ""}."}

          {:error, _} ->
            {:skipped, :cancel_failed}
        end
    end
  end

  # ── Client resolution ──────────────────────────────────────────────────────

  # A job created earlier in this same inbound message whose phone (or, lacking
  # a phone, client name) matches the booking target.
  defp match_created_job(ctx, attrs, phone_norm) do
    created = Map.get(ctx, :created_jobs) || []

    Enum.find(created, fn job ->
      job_phone = Phone.normalize_us(job.phone || "")

      cond do
        job_phone != "" -> job_phone == phone_norm
        true -> same_name?(job.client_name, attrs.client_name)
      end
    end)
  end

  defp same_name?(a, b) when is_binary(a) and is_binary(b) do
    norm = fn s -> s |> String.downcase() |> String.trim() end
    norm.(a) != "" and norm.(a) == norm.(b)
  end

  defp same_name?(_, _), do: false

  defp resolve_client(%{client_id: client_id} = attrs, phone_norm, matched_job, ctx) do
    by_id = if client_id, do: Clients.get_client(client_id, ctx.business_id)

    from_job =
      if matched_job && matched_job.client_id,
        do: Clients.get_client(matched_job.client_id, ctx.business_id)

    existing = by_id || from_job || client_by_phone(ctx.business_id, phone_norm)

    if existing do
      {:ok, existing}
    else
      Clients.create_client(%{
        business_id: ctx.business_id,
        client_name: attrs.client_name,
        phone: Phone.to_e164(phone_norm) || attrs.phone
      })
    end
  end

  defp client_by_phone(_business_id, ""), do: nil

  defp client_by_phone(business_id, phone_norm) do
    business_id
    |> Clients.list_clients()
    |> Enum.find(fn client -> Phone.normalize_us(client.phone || "") == phone_norm end)
  end

  # ── SMS composition / delivery ─────────────────────────────────────────────

  defp deliver_client_sms(e164, body, phone_norm, ctx) do
    _ = Messages.send_sms(e164, body)

    _ =
      SmsConversations.record_client_message(
        ctx.business_id,
        ctx.user_id,
        phone_norm,
        "outbound",
        body
      )

    :ok
  end

  defp notify_client_of_confirmation(request, booking, ctx) do
    with link_id when not is_nil(link_id) <- request.booking_link_id,
         link <- Bookings.get_booking_link!(link_id),
         phone when is_binary(phone) and phone != "" <- link.client_phone_normalized,
         e164 when is_binary(e164) <- Phone.to_e164(phone) do
      business = Businesses.get_business!(ctx.business_id)

      body =
        "You're confirmed with #{business.name} for #{format_window(booking.starts_at, booking.ends_at, ctx)}. " <>
          "Reply to this message if anything changes."

      deliver_client_sms(e164, body, phone, ctx)
    else
      _ -> :ok
    end
  end

  defp notify_client_of_cancellation(booking, reason, ctx) do
    with link_id when not is_nil(link_id) <- booking.booking_link_id,
         link <- Bookings.get_booking_link!(link_id),
         phone when is_binary(phone) and phone != "" <- link.client_phone_normalized,
         e164 when is_binary(e164) <- Phone.to_e164(phone) do
      business = Businesses.get_business!(ctx.business_id)

      body =
        "Your appointment with #{business.name} has been cancelled" <>
          if(reason, do: " (#{reason})", else: "") <>
          ". Reply to this message to reschedule."

      deliver_client_sms(e164, body, phone, ctx)
    else
      _ -> :ok
    end
  end

  # ── Lookups scoped to the acting business ──────────────────────────────────

  defp scoped_link(link_id, business_id) do
    case RompCrm.Repo.get(RompCrm.Bookings.BookingLink, link_id) do
      %{business_id: ^business_id} = link -> link
      _ -> nil
    end
  end

  defp safe_get_request(request_id, business_id) do
    case RompCrm.Repo.get(RompCrm.Bookings.BookingRequest, request_id) do
      %{business_id: ^business_id} = request -> request
      _ -> nil
    end
  end

  defp safe_get_booking(booking_id, business_id) do
    case RompCrm.Repo.get(RompCrm.Bookings.Booking, booking_id) do
      %{business_id: ^business_id} = booking -> booking
      _ -> nil
    end
  end

  # ── Formatting ─────────────────────────────────────────────────────────────

  @doc false
  def booking_url(token) do
    base =
      Application.get_env(:romp_crm, :booking_link_base_url, "https://rompcrm.com/book")
      |> String.trim_trailing("/")

    "#{base}/#{token}"
  end

  @doc false
  def duration_phrase(%{duration_min_minutes: min, duration_max_minutes: max}) do
    cond do
      min == max -> "a #{hours_label(min)} hour job"
      true -> "a #{hours_label(min)}–#{hours_label(max)} hour job"
    end
  end

  defp hours_label(minutes) do
    hours = minutes / 60

    if hours == Float.round(hours) do
      "#{trunc(hours)}"
    else
      "#{hours}"
    end
  end

  defp label_or_job(%{job_type_label: label}) when is_binary(label) and label != "", do: label
  defp label_or_job(_), do: "upcoming job"

  defp display_name(%{client_name: name}, _attrs) when is_binary(name) and name != "", do: name
  defp display_name(_, %{client_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(_, _), do: "the client"

  defp format_window(%DateTime{} = starts_at, %DateTime{} = ends_at, ctx) do
    tz = technician_timezone(ctx)
    local_start = DateTime.shift_zone!(starts_at, tz)
    local_end = DateTime.shift_zone!(ends_at, tz)

    date = Calendar.strftime(local_start, "%A %b %-d")
    "#{date}, #{format_time(local_start)}–#{format_time(local_end)}"
  end

  defp format_time(dt) do
    Calendar.strftime(dt, "%-I:%M %p") |> String.replace(":00 ", " ")
  end

  defp technician_timezone(ctx) do
    case RompCrm.Repo.get(RompCrm.Accounts.User, ctx.user_id) do
      nil -> "America/New_York"
      user -> RompCrm.Scheduling.Prefs.decode(user.scheduling_prefs_json).timezone
    end
  end
end
