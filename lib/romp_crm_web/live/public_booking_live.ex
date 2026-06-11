defmodule RompCrmWeb.PublicBookingLive do
  @moduledoc """
  Customer-facing self-scheduling page at `/book/:token` — no authentication.

  Shows open slots for the technician (sized to the job's estimated duration);
  the customer either taps a slot to confirm a hard booking or submits a
  free-text "soft availability" window for the technician to confirm later.
  """
  use RompCrmWeb, :live_view

  alias RompCrm.Accounts.User
  alias RompCrm.Bookings
  alias RompCrm.Bookings.BookingLink
  alias RompCrm.Businesses
  alias RompCrm.Repo
  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.{AvailabilityEngine, Prefs}
  alias RompCrm.SmsConversations
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @slot_window_days 14

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, :page_title, "Book an appointment")

    case load_link(token) do
      {:active, link} ->
        business = Businesses.get_business!(link.business_id)
        prefs = technician_prefs(link)

        {:ok,
         socket
         |> assign(:state, :active)
         |> assign(:link, link)
         |> assign(:business, business)
         |> assign(:prefs, prefs)
         |> assign(:selected_slot, nil)
         |> assign(:soft_mode, false)
         |> assign(:days, slot_days(link, prefs))}

      {state, link} ->
        {:ok,
         socket
         |> assign(:state, state)
         |> assign(:link, link)
         |> assign(:business, link && Businesses.get_business!(link.business_id))
         |> assign(:days, [])
         |> assign(:selected_slot, nil)
         |> assign(:soft_mode, false)}
    end
  end

  defp load_link(token) do
    case Bookings.get_booking_link_by_token(token) do
      nil ->
        {:invalid, nil}

      %BookingLink{status: "booked"} = link ->
        {:already_booked, link}

      %BookingLink{status: status} = link when status in ["expired", "cancelled"] ->
        {:expired, link}

      %BookingLink{expires_at: %DateTime{} = expires_at} = link ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
          {:expired, link}
        else
          {:active, link}
        end

      link ->
        {:active, link}
    end
  end

  @impl true
  def handle_event("pick_slot", %{"start" => start_iso, "end" => end_iso}, socket) do
    with {:ok, starts_at, _} <- DateTime.from_iso8601(start_iso),
         {:ok, ends_at, _} <- DateTime.from_iso8601(end_iso) do
      {:noreply, assign(socket, :selected_slot, %{start: starts_at, end: ends_at})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_slot", _params, socket) do
    {:noreply, assign(socket, :selected_slot, nil)}
  end

  def handle_event("confirm_slot", _params, %{assigns: %{selected_slot: %{} = slot}} = socket) do
    link = socket.assigns.link
    prefs = socket.assigns.prefs
    duration = max(div(DateTime.diff(slot.end, slot.start, :second), 60), 1)

    with :available <- conflict_status(link, slot, duration, prefs),
         {:ok, booking} <-
           Bookings.create_booking(%{
             business_id: link.business_id,
             technician_user_id: link.technician_user_id,
             booking_link_id: link.id,
             client_id: link.client_id,
             job_id: link.job_id,
             starts_at: slot.start,
             ends_at: slot.end,
             status: "confirmed",
             confirmed_via: "web"
           }) do
      _ = Bookings.mark_booking_link(link, "booked")
      notify_after_web_booking(link, booking, socket.assigns.business, prefs)

      {:noreply,
       socket
       |> assign(:state, :confirmed)
       |> assign(:confirmed_booking, booking)}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry — that time was just taken. Please pick another slot.")
         |> assign(:selected_slot, nil)
         |> assign(:days, slot_days(link, prefs))}
    end
  end

  def handle_event("confirm_slot", _params, socket), do: {:noreply, socket}

  def handle_event("show_soft", _params, socket) do
    {:noreply, assign(socket, soft_mode: true, selected_slot: nil)}
  end

  def handle_event("hide_soft", _params, socket) do
    {:noreply, assign(socket, :soft_mode, false)}
  end

  def handle_event("submit_soft", %{"availability" => text}, socket) do
    link = socket.assigns.link
    text = String.trim(to_string(text))

    if text == "" do
      {:noreply, put_flash(socket, :error, "Tell us when you're generally available.")}
    else
      case Bookings.create_booking_request(%{
             business_id: link.business_id,
             technician_user_id: link.technician_user_id,
             booking_link_id: link.id,
             client_id: link.client_id,
             availability_text: text,
             job_type_label: link.job_type_label,
             duration_min_minutes: link.duration_min_minutes,
             duration_max_minutes: link.duration_max_minutes,
             status: "pending"
           }) do
        {:ok, request} ->
          notify_after_soft_request(link, request, socket.assigns.business)
          {:noreply, assign(socket, :state, :soft_submitted)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Something went wrong — please try again.")}
      end
    end
  end

  ## Slots

  defp slot_days(%BookingLink{} = link, %Prefs{} = prefs) do
    today = DateTime.utc_now() |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()
    to_date = Date.add(today, @slot_window_days - 1)

    case Scheduling.combined_busy_blocks(
           link.business_id,
           link.technician_user_id,
           {today, to_date},
           prefs.timezone
         ) do
      {:ok, busy} ->
        busy
        |> AvailabilityEngine.available_slots(today, to_date, prefs, link.duration_max_minutes)
        |> Enum.reject(&(DateTime.compare(&1.start, DateTime.utc_now()) == :lt))
        |> Enum.group_by(fn slot ->
          slot.start |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()
        end)
        |> Enum.sort_by(fn {date, _} -> date end, Date)
        |> Enum.map(fn {date, slots} ->
          %{
            date: date,
            label: Calendar.strftime(date, "%A, %B %-d"),
            slots: Enum.sort_by(slots, & &1.start, DateTime)
          }
        end)

      _ ->
        []
    end
  end

  defp conflict_status(link, slot, duration, prefs) do
    from_date = slot.start |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()
    to_date = slot.end |> DateTime.shift_zone!(prefs.timezone) |> DateTime.to_date()

    case Scheduling.combined_busy_blocks(
           link.business_id,
           link.technician_user_id,
           {from_date, to_date},
           prefs.timezone
         ) do
      {:ok, busy} -> AvailabilityEngine.check_conflict(busy, slot, duration)
      _ -> :conflict
    end
  end

  ## Notifications

  defp notify_after_web_booking(link, booking, business, prefs) do
    window = format_window(booking.starts_at, booking.ends_at, prefs.timezone)

    # Confirmation SMS to the client + context line in their SMS thread
    if e164 = Phone.to_e164(link.client_phone_normalized) do
      body =
        "You're confirmed with #{business.name} for #{window}. Reply to this message if anything changes."

      _ = Messages.send_sms(e164, body)

      _ =
        SmsConversations.record_client_message(
          link.business_id,
          link.technician_user_id,
          link.client_phone_normalized,
          "outbound",
          body
        )
    end

    # Heads-up SMS to the technician
    notify_technician(
      link,
      "New booking: #{client_name(link)} — #{link.job_type_label} — #{window} (booked online)."
    )
  end

  defp notify_after_soft_request(link, request, business) do
    _ = business

    notify_technician(
      link,
      "#{client_name(link)} sent availability for #{link.job_type_label}: \"#{request.availability_text}\". Confirm a time in Romp CRM."
    )
  end

  defp notify_technician(%BookingLink{} = link, body) do
    with %User{} = tech <- Repo.get(User, link.technician_user_id),
         e164 when is_binary(e164) <- Phone.to_e164(tech.phone_normalized || tech.phone) do
      _ = Messages.send_sms(e164, body)
      :ok
    else
      _ -> :ok
    end
  end

  defp technician_prefs(%BookingLink{} = link) do
    case Repo.get(User, link.technician_user_id) do
      nil -> Prefs.default()
      user -> Prefs.decode(user.scheduling_prefs_json)
    end
  end

  defp client_name(%BookingLink{} = link) do
    link = Repo.preload(link, :client)
    (link.client && link.client.client_name != "" && link.client.client_name) || "A client"
  end

  ## Render helpers

  defp duration_phrase(link) do
    RompCrm.Bookings.Orchestrator.duration_phrase(link)
  end

  defp slot_label(slot, tz) do
    slot.start |> DateTime.shift_zone!(tz) |> Calendar.strftime("%-I:%M %p")
  end

  defp format_window(starts_at, ends_at, tz) do
    local_start = DateTime.shift_zone!(starts_at, tz)
    local_end = DateTime.shift_zone!(ends_at, tz)

    Calendar.strftime(local_start, "%A, %B %-d, %-I:%M %p") <>
      "–" <> Calendar.strftime(local_end, "%-I:%M %p")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-200 px-4 py-8 sm:py-12">
      <div class="mx-auto w-full max-w-lg space-y-4">
        <RompCrmWeb.Layouts.flash_group flash={@flash} />

        <%= case @state do %>
          <% :invalid -> %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body text-center">
                <h1 class="text-lg font-semibold">Hmm, that booking link isn't valid.</h1>
                <p class="text-base-content/70">
                  Double-check the link from your text message, or reply to the text and we'll send a fresh one.
                </p>
              </div>
            </div>
          <% :expired -> %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body text-center">
                <h1 class="text-lg font-semibold">This booking link has expired.</h1>
                <p class="text-base-content/70">
                  Reply to the text message from {(@business && @business.name) || "the business"} and we'll send you a new one.
                </p>
              </div>
            </div>
          <% :already_booked -> %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body text-center">
                <h1 class="text-lg font-semibold">This appointment is already booked.</h1>
                <p class="text-base-content/70">
                  Need to change it? Just reply to the text message from {(@business && @business.name) ||
                    "the business"}.
                </p>
              </div>
            </div>
          <% :confirmed -> %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body text-center">
                <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-success/15">
                  <.icon name="hero-check" class="size-7 text-success" />
                </div>
                <h1 class="text-lg font-semibold">You're confirmed!</h1>
                <p class="text-base-content/80">
                  {@business.name} — {@link.job_type_label}
                </p>
                <p class="font-medium">
                  {format_window(@confirmed_booking.starts_at, @confirmed_booking.ends_at, @prefs.timezone)}
                </p>
                <p class="text-sm text-base-content/60">
                  A confirmation text is on its way. Reply to it if anything changes.
                </p>
              </div>
            </div>
          <% :soft_submitted -> %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body text-center">
                <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-success/15">
                  <.icon name="hero-check" class="size-7 text-success" />
                </div>
                <h1 class="text-lg font-semibold">Thanks — we got your availability.</h1>
                <p class="text-base-content/70">
                  {@business.name} will be in touch by text to lock in an exact time.
                </p>
              </div>
            </div>
          <% :active -> %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body space-y-4">
                <div>
                  <h1 class="text-xl font-semibold">{@business.name}</h1>
                  <p class="text-base-content/80">{@link.job_type_label}</p>
                  <p class="text-sm text-base-content/60">
                    Estimated time on site: {duration_phrase(@link)}
                  </p>
                </div>

                <%= if @soft_mode do %>
                  <form phx-submit="submit_soft" class="space-y-3">
                    <label class="block text-sm font-medium" for="availability">
                      When are you generally available?
                    </label>
                    <textarea
                      id="availability"
                      name="availability"
                      rows="3"
                      class="textarea textarea-bordered w-full"
                      placeholder="e.g. Any weekday after 3pm, or all day Thursday"
                    ></textarea>
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary flex-1">Send availability</button>
                      <button type="button" class="btn btn-ghost" phx-click="hide_soft">Back</button>
                    </div>
                  </form>
                <% else %>
                  <%= if @selected_slot do %>
                    <div class="rounded-lg border border-primary/40 bg-primary/5 p-4 text-center space-y-3">
                      <p class="font-medium">
                        {format_window(@selected_slot.start, @selected_slot.end, @prefs.timezone)}
                      </p>
                      <div class="flex gap-2">
                        <button type="button" class="btn btn-primary flex-1" phx-click="confirm_slot">
                          Confirm this time
                        </button>
                        <button type="button" class="btn btn-ghost" phx-click="clear_slot">
                          Change
                        </button>
                      </div>
                    </div>
                  <% else %>
                    <%= if @days == [] do %>
                      <p class="text-base-content/70">
                        No open times in the next two weeks. Tap below to send your availability instead.
                      </p>
                    <% else %>
                      <div class="space-y-4 max-h-[26rem] overflow-y-auto pr-1">
                        <div :for={day <- @days}>
                          <h2 class="mb-2 text-sm font-semibold text-base-content/70">{day.label}</h2>
                          <div class="grid grid-cols-3 gap-2">
                            <button
                              :for={slot <- day.slots}
                              type="button"
                              class="btn btn-outline btn-sm"
                              phx-click="pick_slot"
                              phx-value-start={DateTime.to_iso8601(slot.start)}
                              phx-value-end={DateTime.to_iso8601(slot.end)}
                            >
                              {slot_label(slot, @prefs.timezone)}
                            </button>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  <% end %>

                  <div class="border-t border-base-300 pt-3 text-center">
                    <button type="button" class="link link-hover text-sm" phx-click="show_soft">
                      None of these work? Send us your availability
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
            <p class="text-center text-xs text-base-content/50">
              Scheduling powered by Romp CRM
            </p>
        <% end %>
      </div>
    </main>
    """
  end
end
