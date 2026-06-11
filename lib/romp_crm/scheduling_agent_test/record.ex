defmodule RompCrm.SchedulingAgentTest.Record do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "scheduling_agent_test_sessions" do
    field :state_json, :string
    belongs_to :user, RompCrm.Accounts.User
    belongs_to :business, RompCrm.Businesses.Business

    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:user_id, :business_id, :state_json])
    |> validate_required([:user_id, :business_id, :state_json])
    |> unique_constraint([:user_id, :business_id])
  end
end
