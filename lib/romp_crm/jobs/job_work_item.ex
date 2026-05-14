defmodule RompCrm.Jobs.JobWorkItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "job_work_items" do
    belongs_to :job, RompCrm.Jobs.Job

    field :title, :string
    field :sort_order, :integer, default: 0
    field :scheduled_on, :date
    field :scheduled_time, :time
    field :completed, :boolean, default: false

    has_many :materials, RompCrm.Jobs.JobMaterial, foreign_key: :job_work_item_id
    has_many :photos, RompCrm.Jobs.JobPhoto, foreign_key: :job_work_item_id

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:job_id, :title, :sort_order, :scheduled_on, :scheduled_time, :completed])
    |> validate_length(:title, max: 8000)
  end
end
