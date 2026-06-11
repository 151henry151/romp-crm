defmodule RompCrm.SmsPendingBookingProposals.Pending do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "sms_pending_booking_proposals" do
    field :phone_normalized, :string
    field :proposal_json, :string
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(pending, attrs) do
    pending
    |> cast(attrs, [:business_id, :user_id, :phone_normalized, :proposal_json])
    |> validate_required([:business_id, :user_id, :phone_normalized, :proposal_json])
    |> unique_constraint([:business_id, :phone_normalized])
  end
end
