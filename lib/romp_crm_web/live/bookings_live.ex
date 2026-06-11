defmodule RompCrmWeb.BookingsLive do
  @moduledoc """
  Technician booking management: pending soft-availability requests (with the
  confirm flow), active booking links (duration edit, cancel, copy URL), and
  upcoming confirmed bookings. Confirm/cancel/duration actions run through
  `RompCrm.Bookings.Orchestrator` so client SMS notifications match the agent
  flow.
  """

  use RompCrmWeb, :live_view

  alias RompCrm.Bookings
  alias RompCrm.Bookings.Orchestrator
  alias RompCrm.Scheduling.Prefs

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id
    prefs = Prefs.decode(user.scheduling_prefs_json)

    {:ok,
     socket
     |> assign(:page_title, "Bookings")
     |> assign(:tz, prefs.timezone)
     |> assign(:is_business_owner, RompCrm.Businesses.owner?(user, bid))
     |> assign(:confirming_request_id, nil)
     |> assign(:editing_link_id, nil)
     |> load_data()}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end

  ## Soft-availability confirm flow

  @impl true
  def handle_event("confirm_start", %{"request_id" => id}, socket) do
    {:noreply, assign(socket, :confirming_request_id, parse_int(id))}
  end

  def handle_event("confirm_cancel", _params, socket) do
    {:noreply, assign(socket, :confirming_request_id, nil)}
  end

  def handle_event("confirm_request", params, socket) do
    id = parse_int(params["request_id"])
    date = params |> Map.get("date", "") |> String.trim()
    time = params |> Map.get("time", "") |> String.trim()
    duration = parse_int(params["duration_minutes"])

    with request when not is_nil(request) <- find_request(socket, id),
         {:ok, starts_at} <- local_to_utc(date, time, socket.assigns.tz),
         duration when is_integer(duration) and duration > 0 <- duration do
      ends_at = DateTime.add(starts_at, duration, :minute)

      case run_op({:booking_confirm_soft, request.id, starts_at, ends_at}, socket) do
        {:booking_done, summary} ->
          {:noreply,
           socket
           |> put_flash(:info, summary <> " The client has been texted.")
           |> assign(:confirming_request_id, nil)
           |> load_data()}

        {:skipped, reason} ->
          {:noreply, put_flash(socket, :error, "Could not confirm (#{reason}).")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Pick a valid date, time, and duration.")}
    end
  end

  def handle_event("dismiss_request", %{"request_id" => id}, socket) do
    case find_request(socket, parse_int(id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Request not found.")}

      request ->
        case Bookings.cancel_booking_request(request) do
          {:ok, _} ->
            {:noreply,
             socket |> put_flash(:info, "Availability request dismissed.") |> load_data()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not dismiss the request.")}
        end
    end
  end

  ## Booking link actions

  def handle_event("edit_duration_start", %{"link_id" => id}, socket) do
    {:noreply, assign(socket, :editing_link_id, parse_int(id))}
  end

  def handle_event("edit_duration_cancel", _params, socket) do
    {:noreply, assign(socket, :editing_link_id, nil)}
  end

  def handle_event("edit_duration_save", params, socket) do
    id = parse_int(params["link_id"])
    min_minutes = parse_int(params["min_minutes"])
    max_minutes = parse_int(params["max_minutes"])

    if is_integer(min_minutes) and is_integer(max_minutes) and min_minutes > 0 and
         max_minutes >= min_minutes do
      case run_op({:booking_update_duration, id, min_minutes, max_minutes}, socket) do
        {:booking_done, summary} ->
          {:noreply,
           socket
           |> put_flash(:info, summary)
           |> assign(:editing_link_id, nil)
           |> load_data()}

        {:skipped, reason} ->
          {:noreply, put_flash(socket, :error, "Could not update (#{reason}).")}
      end
    else
      {:noreply, put_flash(socket, :error, "Enter a valid duration range in minutes.")}
    end
  end

  def handle_event("cancel_link", %{"link_id" => id}, socket) do
    case find_link(socket, parse_int(id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Booking link not found.")}

      link ->
        case Bookings.mark_booking_link(link, "cancelled") do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, "Booking link cancelled.") |> load_data()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not cancel the link.")}
        end
    end
  end

  ## Booking actions

  def handle_event("cancel_booking", %{"booking_id" => id}, socket) do
    case run_op({:booking_cancel, parse_int(id), nil}, socket) do
      {:booking_done, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Booking cancelled. The client has been texted.")
         |> load_data()}

      {:skipped, reason} ->
        {:noreply, put_flash(socket, :error, "Could not cancel (#{reason}).")}
    end
  end

  ## Data loading

  defp load_data(socket) do
    bid = socket.assigns.current_business_id

    socket
    |> assign(:requests, Bookings.list_pending_booking_requests(bid))
    |> assign(:links, Bookings.list_active_links(bid))
    |> assign(:bookings, Bookings.list_upcoming_bookings(bid))
  end

  defp run_op(op, socket) do
    ctx = %{
      business_id: socket.assigns.current_business_id,
      user_id: socket.assigns.current_scope.user.id,
      message_sid: "web"
    }

    {:ok, [result]} = Orchestrator.run_operations([op], ctx)
    result
  end

  defp find_request(socket, id), do: Enum.find(socket.assigns.requests, &(&1.id == id))
  defp find_link(socket, id), do: Enum.find(socket.assigns.links, &(&1.id == id))

  defp local_to_utc(date, time, tz) do
    with {:ok, d} <- Date.from_iso8601(date),
         {:ok, t} <- Time.from_iso8601(pad_time(time)) do
      case DateTime.new(d, t, tz) do
        {:ok, dt} -> {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}
        {:gap, _b, a} -> {:ok, DateTime.shift_zone!(a, "Etc/UTC")}
        {:ambiguous, f, _s} -> {:ok, DateTime.shift_zone!(f, "Etc/UTC")}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp pad_time(time) do
    if Regex.match?(~r/^\d{2}:\d{2}$/, time), do: time <> ":00", else: time
  end

  defp parse_int(v) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  ## Template helpers

  def client_name(%{client: %{client_name: name}}) when is_binary(name) and name != "", do: name
  def client_name(_), do: "Client"

  def job_label(%{job_type_label: label}) when is_binary(label) and label != "", do: label
  def job_label(_), do: "Job"

  def duration_text(%{duration_min_minutes: min, duration_max_minutes: max} = item)
      when is_integer(min) and is_integer(max),
      do: Orchestrator.duration_phrase(item)

  def duration_text(_), do: "duration not set"

  def booking_url(token), do: Orchestrator.booking_url(token)

  def window_text(%DateTime{} = starts_at, %DateTime{} = ends_at, tz) do
    local_start = DateTime.shift_zone!(starts_at, tz)
    local_end = DateTime.shift_zone!(ends_at, tz)

    Calendar.strftime(local_start, "%A %b %-d") <>
      ", " <> format_time(local_start) <> "–" <> format_time(local_end)
  end

  defp format_time(dt) do
    Calendar.strftime(dt, "%-I:%M %p") |> String.replace(":00 ", " ")
  end
end
