defmodule RompCrm.Businesses.BusinessInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  @hash_algorithm :sha256

  schema "business_invitations" do
    field :email, :string
    field :token_hash, :binary

    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :invited_by_user, RompCrm.Accounts.User, foreign_key: :invited_by_user_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def token_validity_in_days, do: 7

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:business_id, :invited_by_user_id, :email, :token_hash])
    |> validate_required([:business_id, :email, :token_hash])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> unique_constraint(:token_hash)
  end

  def hash_raw_token(raw) when is_binary(raw) do
    :crypto.hash(@hash_algorithm, raw)
  end
end
