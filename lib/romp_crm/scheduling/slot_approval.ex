defmodule RompCrm.Scheduling.SlotApproval do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "booking_slot_approvals" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :technician_user, RompCrm.Accounts.User, foreign_key: :technician_user_id
    belongs_to :booking_link, RompCrm.Bookings.BookingLink

    field :client_phone_normalized, :string
    field :local_offerings_json, :string
    field :open_slots_json, :string
    field :customer_pending_reply, :string
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [
      :business_id,
      :technician_user_id,
      :booking_link_id,
      :client_phone_normalized,
      :local_offerings_json,
      :open_slots_json,
      :customer_pending_reply,
      :status
    ])
    |> validate_required([
      :business_id,
      :technician_user_id,
      :booking_link_id,
      :client_phone_normalized,
      :local_offerings_json,
      :status
    ])
    |> validate_inclusion(:status, ~w(pending approved rejected))
  end
end
