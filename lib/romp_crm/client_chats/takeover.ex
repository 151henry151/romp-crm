defmodule RompCrm.ClientChats.Takeover do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "client_chat_takeovers" do
    field :phone_normalized, :string
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :booking_link, RompCrm.Bookings.BookingLink
    belongs_to :taken_over_by_user, RompCrm.Accounts.User, foreign_key: :taken_over_by_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(takeover, attrs) do
    takeover
    |> cast(attrs, [:business_id, :booking_link_id, :phone_normalized, :taken_over_by_user_id])
    |> validate_required([:business_id, :phone_normalized, :taken_over_by_user_id])
    |> unique_constraint([:business_id, :phone_normalized])
  end
end
