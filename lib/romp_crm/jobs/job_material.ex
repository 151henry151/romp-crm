defmodule RompCrm.Jobs.JobMaterial do
  use Ecto.Schema
  import Ecto.Changeset

  schema "job_materials" do
    belongs_to :job, RompCrm.Jobs.Job
    belongs_to :job_work_item, RompCrm.Jobs.JobWorkItem

    field :description, :string
    field :sort_order, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:job_id, :job_work_item_id, :description, :sort_order])
    |> validate_required([:job_id, :description])
    |> validate_length(:description, max: 4000)
  end
end
