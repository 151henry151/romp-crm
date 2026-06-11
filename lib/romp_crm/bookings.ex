defmodule RompCrm.Bookings do
  @moduledoc """
  Customer self-scheduling: booking links (`/book/:token` plus SMS context),
  confirmed bookings, and soft-availability booking requests.

  Booking links expire after #{14} days by default; `expire_stale_links/0`
  is run periodically by the scheduler tick.
  """

  import Ecto.Query

  alias RompCrm.Bookings.{Booking, BookingLink, BookingRequest}
  alias RompCrm.Repo

  @default_expiry_days 14

  ## Booking links

  @doc """
  Creates a booking link, generating a unique URL-safe token and a default
  expiry of #{@default_expiry_days} days when not supplied.
  """
  def create_booking_link(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:token, generate_token())
      |> Map.put_new(
        :expires_at,
        DateTime.add(DateTime.utc_now(:second), @default_expiry_days, :day)
      )

    %BookingLink{}
    |> BookingLink.changeset(attrs)
    |> Repo.insert()
  end

  def get_booking_link_by_token(token) when is_binary(token) do
    token = String.trim(token)

    if token == "" do
      nil
    else
      Repo.get_by(BookingLink, token: token)
    end
  end

  def get_booking_link!(id), do: Repo.get!(BookingLink, id)

  @doc """
  All pending, unexpired booking links for a client phone, newest first —
  across **all** businesses (shared Twilio number means one client phone can
  have active conversations with more than one business; callers must
  disambiguate before acting when more than one row returns).
  """
  def active_links_for_client_phone(phone_normalized) when is_binary(phone_normalized) do
    now = DateTime.utc_now(:second)

    Repo.all(
      from l in BookingLink,
        where: l.client_phone_normalized == ^phone_normalized,
        where: l.status == "pending",
        where: is_nil(l.expires_at) or l.expires_at > ^now,
        order_by: [desc: l.id]
    )
  end

  @doc "Transitions a booking link to the given status."
  def mark_booking_link(%BookingLink{} = link, status) when status in ~w(pending booked expired cancelled) do
    link
    |> BookingLink.changeset(%{status: status})
    |> Repo.update()
  end

  @doc "Updates the duration estimate on a link (technician edit)."
  def update_link_duration(%BookingLink{} = link, min_minutes, max_minutes) do
    link
    |> BookingLink.changeset(%{
      duration_min_minutes: min_minutes,
      duration_max_minutes: max_minutes
    })
    |> Repo.update()
  end

  @doc "Pending, unexpired booking links for a business, newest first, client preloaded."
  def list_active_links(business_id) when is_integer(business_id) do
    now = DateTime.utc_now(:second)

    Repo.all(
      from l in BookingLink,
        where: l.business_id == ^business_id and l.status == "pending",
        where: is_nil(l.expires_at) or l.expires_at > ^now,
        order_by: [desc: l.id],
        preload: [:client]
    )
  end

  @doc "Reads one intake flag from a booking link's JSON blob."
  def intake_flag?(%BookingLink{} = link, key) when is_binary(key) do
    link.intake_flags_json
    |> decode_intake_flags()
    |> Map.get(key) == true
  end

  @doc "Sets one intake flag and persists the JSON blob."
  def mark_intake_flag(%BookingLink{} = link, key, value)
      when is_binary(key) and is_boolean(value) do
    flags =
      link.intake_flags_json
      |> decode_intake_flags()
      |> Map.put(key, value)

    link
    |> BookingLink.changeset(%{intake_flags_json: Jason.encode!(flags)})
    |> Repo.update()
  end

  defp decode_intake_flags(nil), do: %{}
  defp decode_intake_flags(""), do: %{}

  defp decode_intake_flags(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> map
      _ -> %{}
    end
  end

  @doc "Marks pending links past their expiry as expired; returns the count."
  def expire_stale_links do
    now = DateTime.utc_now(:second)

    {count, _} =
      Repo.update_all(
        from(l in BookingLink,
          where: l.status == "pending",
          where: not is_nil(l.expires_at) and l.expires_at <= ^now
        ),
        set: [status: "expired", updated_at: now]
      )

    count
  end

  ## Bookings

  def create_booking(attrs) when is_map(attrs) do
    %Booking{}
    |> Booking.changeset(attrs)
    |> Repo.insert()
  end

  def get_booking!(id), do: Repo.get!(Booking, id)

  def cancel_booking(%Booking{} = booking) do
    booking
    |> Booking.changeset(%{status: "cancelled"})
    |> Repo.update()
  end

  @doc "Confirmed bookings for a business overlapping the UTC window, oldest first."
  def list_confirmed_bookings(business_id, %DateTime{} = from_utc, %DateTime{} = to_utc)
      when is_integer(business_id) do
    Repo.all(
      from b in Booking,
        where: b.business_id == ^business_id,
        where: b.status == "confirmed",
        where: b.starts_at < ^to_utc and b.ends_at > ^from_utc,
        order_by: [asc: b.starts_at]
    )
  end

  @doc "Confirmed bookings ending in the future for a business, soonest first, client preloaded."
  def list_upcoming_bookings(business_id) when is_integer(business_id) do
    now = DateTime.utc_now(:second)

    Repo.all(
      from b in Booking,
        where: b.business_id == ^business_id and b.status == "confirmed",
        where: b.ends_at > ^now,
        order_by: [asc: b.starts_at],
        preload: [:client, :booking_link]
    )
  end

  ## Booking requests (soft availability)

  def create_booking_request(attrs) when is_map(attrs) do
    %BookingRequest{}
    |> BookingRequest.changeset(attrs)
    |> Repo.insert()
  end

  def get_booking_request!(id), do: Repo.get!(BookingRequest, id)

  @doc "Pending soft-availability requests for a business, newest first."
  def list_pending_booking_requests(business_id) when is_integer(business_id) do
    Repo.all(
      from r in BookingRequest,
        where: r.business_id == ^business_id and r.status == "pending",
        order_by: [desc: r.id],
        preload: [:client, :booking_link]
    )
  end

  @doc """
  Converts a soft-availability request into a confirmed booking: inserts the
  booking, marks the request converted, and marks the linked booking link booked.
  One transaction; returns `{:ok, booking}` or `{:error, changeset}`.
  """
  def confirm_booking_request(%BookingRequest{} = request, slot_attrs) when is_map(slot_attrs) do
    booking_attrs =
      slot_attrs
      |> Map.put(:business_id, request.business_id)
      |> Map.put(:technician_user_id, request.technician_user_id)
      |> Map.put(:booking_link_id, request.booking_link_id)
      |> Map.put(:client_id, request.client_id)
      |> Map.put_new(:confirmed_via, "technician")

    Repo.transaction(fn ->
      with {:ok, booking} <- create_booking(booking_attrs),
           {:ok, _} <-
             request |> BookingRequest.changeset(%{status: "converted"}) |> Repo.update(),
           :ok <- maybe_mark_link_booked(request.booking_link_id),
           _ <- RompCrm.Bookings.JobScheduleSync.sync_from_booking(booking) do
        booking
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def cancel_booking_request(%BookingRequest{} = request) do
    request
    |> BookingRequest.changeset(%{status: "cancelled"})
    |> Repo.update()
  end

  defp maybe_mark_link_booked(nil), do: :ok

  defp maybe_mark_link_booked(link_id) do
    case Repo.get(BookingLink, link_id) do
      nil ->
        :ok

      link ->
        case mark_booking_link(link, "booked") do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Display address for the work behind a booking link: the linked job's service
  address when set, else the client's. Nil when neither has one.
  """
  def service_address_for_link(%BookingLink{} = link) do
    job = link.job_id && Repo.get(RompCrm.Jobs.Job, link.job_id)
    client = link.client_id && Repo.get(RompCrm.Clients.Client, link.client_id)

    [job, client]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn record ->
      case RompCrm.Addresses.format_service(record) do
        addr when is_binary(addr) and addr not in ["", "—"] -> addr
        _ -> nil
      end
    end)
  end

  ## AI snapshot

  @doc """
  Booking context for the unified SMS prompt: active booking links, pending
  soft-availability requests, and upcoming confirmed bookings for the business.
  String-keyed for direct JSON encoding into the prompt.
  """
  def snapshot_for_sms_ai(business_id) when is_integer(business_id) do
    now = DateTime.utc_now(:second)

    links =
      Repo.all(
        from l in BookingLink,
          where: l.business_id == ^business_id and l.status == "pending",
          where: is_nil(l.expires_at) or l.expires_at > ^now,
          order_by: [desc: l.id],
          limit: 25,
          preload: [:client]
      )
      |> Enum.map(fn l ->
        %{
          "booking_link_id" => l.id,
          "client_id" => l.client_id,
          "client_name" => l.client && l.client.client_name,
          "client_phone" => l.client_phone_normalized,
          "job_type_label" => l.job_type_label,
          "duration_min_minutes" => l.duration_min_minutes,
          "duration_max_minutes" => l.duration_max_minutes,
          "expires_at" => l.expires_at && DateTime.to_iso8601(l.expires_at)
        }
      end)

    requests =
      Repo.all(
        from r in BookingRequest,
          where: r.business_id == ^business_id and r.status == "pending",
          order_by: [desc: r.id],
          limit: 25,
          preload: [:client]
      )
      |> Enum.map(fn r ->
        %{
          "booking_request_id" => r.id,
          "booking_link_id" => r.booking_link_id,
          "client_id" => r.client_id,
          "client_name" => r.client && r.client.client_name,
          "availability_text" => r.availability_text,
          "job_type_label" => r.job_type_label
        }
      end)

    bookings =
      Repo.all(
        from b in Booking,
          where: b.business_id == ^business_id and b.status == "confirmed",
          where: b.ends_at > ^now,
          order_by: [asc: b.starts_at],
          limit: 25,
          preload: [:client]
      )
      |> Enum.map(fn b ->
        %{
          "booking_id" => b.id,
          "client_id" => b.client_id,
          "client_name" => b.client && b.client.client_name,
          "starts_at" => DateTime.to_iso8601(b.starts_at),
          "ends_at" => DateTime.to_iso8601(b.ends_at)
        }
      end)

    %{
      "active_booking_links" => links,
      "pending_booking_requests" => requests,
      "upcoming_bookings" => bookings
    }
  end

  defp generate_token do
    Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end
end
