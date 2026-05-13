defmodule RompCrm.Jobs.JobPhoto do
  use Ecto.Schema
  import Ecto.Changeset

  schema "job_photos" do
    belongs_to :job, RompCrm.Jobs.Job
    belongs_to :job_work_item, RompCrm.Jobs.JobWorkItem

    field :relative_path, :string
    field :content_type, :string
    field :byte_size, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:job_id, :job_work_item_id, :relative_path, :content_type, :byte_size])
    |> validate_required([:job_id, :relative_path])
    |> validate_length(:relative_path, max: 500)
  end
end
