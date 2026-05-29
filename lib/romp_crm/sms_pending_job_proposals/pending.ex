defmodule RompCrm.SmsPendingJobProposals.Pending do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sms_pending_job_proposals" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User

    field :phone_normalized, :string
    field :image_kind, :string
    field :proposals_json, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:business_id, :user_id, :phone_normalized, :image_kind, :proposals_json])
    |> validate_required([:business_id, :user_id, :phone_normalized, :proposals_json])
    |> validate_length(:phone_normalized, max: 32)
    |> validate_length(:image_kind, max: 64)
    |> unique_constraint([:business_id, :phone_normalized])
  end
end
