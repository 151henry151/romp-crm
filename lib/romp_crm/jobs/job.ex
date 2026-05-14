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
    field :scheduled_on, :date
    field :scheduled_time, :time

    has_many :work_items, RompCrm.Jobs.JobWorkItem, on_replace: :delete
    has_many :materials, RompCrm.Jobs.JobMaterial
    has_many :photos, RompCrm.Jobs.JobPhoto

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
      :next_action,
      :scheduled_on,
      :scheduled_time
    ])
    |> cast_assoc(:work_items,
      with: &RompCrm.Jobs.JobWorkItem.changeset/2,
      sort_param: :work_items_sort,
      drop_param: :work_items_drop
    )
    |> validate_required([:business_id, :client_name, :priority, :status])
  end
end
