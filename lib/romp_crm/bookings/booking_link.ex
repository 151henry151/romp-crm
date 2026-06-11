defmodule RompCrm.Bookings.BookingLink do
  @moduledoc """
  A customer-facing scheduling invitation: unique URL token plus the job/duration
  context the AI agent and the public `/book/:token` page both work from.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending booked expired cancelled)

  schema "booking_links" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :technician_user, RompCrm.Accounts.User
    belongs_to :client, RompCrm.Clients.Client
    belongs_to :job, RompCrm.Jobs.Job

    field :token, :string
    field :job_type_label, :string, default: ""
    field :duration_min_minutes, :integer, default: 60
    field :duration_max_minutes, :integer, default: 120
    field :client_phone_normalized, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    field :intake_flags_json, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :business_id,
      :technician_user_id,
      :client_id,
      :job_id,
      :token,
      :job_type_label,
      :duration_min_minutes,
      :duration_max_minutes,
      :client_phone_normalized,
      :status,
      :expires_at,
      :intake_flags_json
    ])
    |> validate_required([:business_id, :technician_user_id, :token, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:duration_min_minutes, greater_than: 0, less_than_or_equal_to: 24 * 60)
    |> validate_number(:duration_max_minutes, greater_than: 0, less_than_or_equal_to: 24 * 60)
    |> validate_duration_order()
    |> validate_length(:job_type_label, max: 200)
    |> unique_constraint(:token)
  end

  defp validate_duration_order(changeset) do
    min = get_field(changeset, :duration_min_minutes)
    max = get_field(changeset, :duration_max_minutes)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(changeset, :duration_max_minutes, "must be at least the minimum duration")
    else
      changeset
    end
  end
end
