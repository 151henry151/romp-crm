defmodule RompCrm.Repo.Migrations.JobWorkItemsMaterialsPhotosScheduled do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :scheduled_on, :date
    end

    create table(:job_work_items) do
      add :job_id, references(:jobs, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :sort_order, :integer, null: false, default: 0
      add :scheduled_on, :date

      timestamps(type: :utc_datetime)
    end

    create index(:job_work_items, [:job_id])

    create table(:job_materials) do
      add :job_id, references(:jobs, on_delete: :delete_all), null: false
      add :job_work_item_id, references(:job_work_items, on_delete: :delete_all)
      add :description, :text, null: false
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:job_materials, [:job_id])
    create index(:job_materials, [:job_work_item_id])

    create table(:job_photos) do
      add :job_id, references(:jobs, on_delete: :delete_all), null: false
      add :job_work_item_id, references(:job_work_items, on_delete: :nilify_all)
      add :relative_path, :string, null: false
      add :content_type, :string
      add :byte_size, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:job_photos, [:job_id])
    create index(:job_photos, [:job_work_item_id])
  end
end
