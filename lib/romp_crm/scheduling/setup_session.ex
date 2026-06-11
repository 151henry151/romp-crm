defmodule RompCrm.Scheduling.SetupSession do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "sms_scheduling_setup_sessions" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User

    field :phone_normalized, :string
    field :phase, :string, default: "awaiting_structured"
    field :held_intent_json, :string
    field :structured_answers_json, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :business_id,
      :user_id,
      :phone_normalized,
      :phase,
      :held_intent_json,
      :structured_answers_json
    ])
    |> validate_required([:business_id, :user_id, :phone_normalized, :phase])
    |> validate_inclusion(:phase, ~w(awaiting_structured awaiting_open_ended))
    |> unique_constraint([:business_id, :phone_normalized])
  end
end
