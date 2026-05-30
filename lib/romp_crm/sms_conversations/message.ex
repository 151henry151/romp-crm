defmodule RompCrm.SmsConversations.Message do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "sms_conversation_messages" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User

    field :phone_normalized, :string
    field :direction, :string
    field :channel, :string, default: "sms"
    field :body, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:business_id, :user_id, :phone_normalized, :direction, :channel, :body])
    |> validate_required([:business_id, :user_id, :phone_normalized, :direction, :body])
    |> validate_inclusion(:direction, ["inbound", "outbound"])
    |> validate_inclusion(:channel, ["sms", "in_app"])
    |> validate_length(:body, max: 6000)
  end
end
