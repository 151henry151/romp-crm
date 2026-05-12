defmodule RompCrm.SmsInteractionLogs.Log do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "sms_interaction_logs" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User

    field :twilio_message_sid, :string
    field :phone_normalized, :string
    field :outcome, :string
    field :inbound_body, :string
    field :outbound_body, :string
    field :planned_operations, :string
    field :results_summary, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :business_id,
      :user_id,
      :twilio_message_sid,
      :phone_normalized,
      :outcome,
      :inbound_body,
      :outbound_body,
      :planned_operations,
      :results_summary
    ])
    |> validate_required([:business_id, :user_id, :outcome])
    |> validate_length(:inbound_body, max: 4000)
    |> validate_length(:outbound_body, max: 4000)
    |> validate_length(:planned_operations, max: 32_000)
    |> validate_length(:results_summary, max: 32_000)
  end
end
