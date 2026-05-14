defmodule RompCrm.Gifts.GiftSubscription do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "gift_subscriptions" do
    field :token, :string
    field :recipient_email, :string
    field :duration_days, :integer
    field :admin_message, :string
    field :redeemed_at, :utc_datetime

    belongs_to :created_by_user, RompCrm.Accounts.User, foreign_key: :created_by_user_id
    belongs_to :redeemed_user, RompCrm.Accounts.User, foreign_key: :redeemed_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(struct, attrs) when is_map(attrs) do
    struct
    |> cast(attrs, [:token, :recipient_email, :duration_days, :admin_message, :created_by_user_id])
    |> validate_required([:token, :recipient_email, :duration_days, :created_by_user_id])
    |> validate_number(:duration_days, greater_than: 0, less_than_or_equal_to: 3650)
    |> validate_length(:recipient_email, max: 160)
    |> validate_length(:admin_message, max: 2000)
    |> update_change(:recipient_email, &normalize_email/1)
    |> unique_constraint(:token)
  end

  defp normalize_email(email) do
    email |> to_string() |> String.trim() |> String.downcase()
  end
end
