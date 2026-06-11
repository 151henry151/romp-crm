defmodule RompCrm.Bookings.Booking do
  @moduledoc """
  A confirmed appointment. Times are stored UTC; display happens in the
  technician's or client's local timezone.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(confirmed cancelled rescheduled)
  @confirmed_via ~w(web sms technician)

  schema "bookings" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :technician_user, RompCrm.Accounts.User
    belongs_to :booking_link, RompCrm.Bookings.BookingLink
    belongs_to :client, RompCrm.Clients.Client
    belongs_to :job, RompCrm.Jobs.Job

    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :status, :string, default: "confirmed"
    field :confirmed_via, :string, default: "web"

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, [
      :business_id,
      :technician_user_id,
      :booking_link_id,
      :client_id,
      :job_id,
      :starts_at,
      :ends_at,
      :status,
      :confirmed_via
    ])
    |> validate_required([:business_id, :technician_user_id, :starts_at, :ends_at, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:confirmed_via, @confirmed_via)
    |> validate_time_order()
  end

  defp validate_time_order(changeset) do
    starts = get_field(changeset, :starts_at)
    ends = get_field(changeset, :ends_at)

    if is_struct(starts, DateTime) and is_struct(ends, DateTime) and
         DateTime.compare(starts, ends) != :lt do
      add_error(changeset, :ends_at, "must be after the start time")
    else
      changeset
    end
  end
end
