defmodule RompCrm.Businesses.Business do
  use Ecto.Schema
  import Ecto.Changeset

  schema "businesses" do
    field :name, :string

    has_many :business_memberships, RompCrm.Businesses.BusinessMembership
    has_many :jobs, RompCrm.Jobs.Job

    timestamps(type: :utc_datetime)
  end

  def changeset(business, attrs) do
    business
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
  end
end
