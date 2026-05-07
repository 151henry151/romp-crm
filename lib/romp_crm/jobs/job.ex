defmodule RompCrm.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @priorities [:normal, :high]
  @statuses [:lead, :pending, :in_progress, :done]

  def priorities, do: @priorities
  def statuses, do: @statuses

  schema "jobs" do
    belongs_to :business, RompCrm.Businesses.Business

    field :client_name, :string
    field :address, :string
    field :phone, :string
    field :work_description, :string
    field :priority, Ecto.Enum, values: @priorities, default: :normal
    field :status, Ecto.Enum, values: @statuses, default: :lead
    field :referred_by, :string
    field :notes, :string
    field :next_action, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :business_id,
      :client_name,
      :address,
      :phone,
      :work_description,
      :priority,
      :status,
      :referred_by,
      :notes,
      :next_action
    ])
    |> validate_required([:business_id, :client_name, :priority, :status])
  end
end
