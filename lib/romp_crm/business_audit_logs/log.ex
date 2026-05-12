defmodule RompCrm.BusinessAuditLogs.Log do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "business_audit_logs" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :actor_user, RompCrm.Accounts.User, foreign_key: :actor_user_id

    field :source, :string
    field :action, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :metadata, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :business_id,
      :actor_user_id,
      :source,
      :action,
      :entity_type,
      :entity_id,
      :metadata
    ])
    |> validate_required([:business_id, :actor_user_id, :source, :action, :entity_type])
  end
end
