defmodule RompCrm.SmsInboundRolePrompts.RolePrompt do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "sms_inbound_role_prompts" do
    field :phone_normalized, :string
    field :booking_business_names_json, :string
    belongs_to :user, RompCrm.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, [:phone_normalized, :user_id, :booking_business_names_json])
    |> validate_required([:phone_normalized, :user_id, :booking_business_names_json])
    |> unique_constraint(:phone_normalized)
  end
end
