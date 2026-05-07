defmodule RompCrm.Businesses.BusinessMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles [:owner, :member]

  schema "business_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member

    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:business_id, :user_id, :role])
    |> validate_required([:business_id, :user_id, :role])
    |> unique_constraint([:business_id, :user_id])
  end
end
