defmodule RompCrm.Bookings.SchedulingMemory do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "scheduling_memories" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :source_escalation, RompCrm.Bookings.Escalation

    field :topic, :string
    field :answer_text, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:business_id, :topic, :answer_text, :source_escalation_id])
    |> validate_required([:business_id, :topic, :answer_text])
    |> validate_length(:topic, max: 300)
  end
end
