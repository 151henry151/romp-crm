defmodule RompCrm.Scheduling.PlaybookRule do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "scheduling_playbook_rules" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :technician_user, RompCrm.Accounts.User, foreign_key: :technician_user_id

    field :kind, :string
    field :config, :map, default: %{}
    field :source_text, :string
    field :active, :boolean, default: true
    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @kinds ~w(
    greeting_template
    customer_outreach_style
    confirm_before_offer_slots
    min_lead_days
    scheduling_bias
    custom_instruction
  )

  def kinds, do: @kinds

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :business_id,
      :technician_user_id,
      :kind,
      :config,
      :source_text,
      :active,
      :priority
    ])
    |> validate_required([:business_id, :technician_user_id, :kind, :config])
    |> validate_inclusion(:kind, @kinds)
  end
end
