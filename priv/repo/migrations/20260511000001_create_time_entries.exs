defmodule RompCrm.Repo.Migrations.CreateTimeEntries do
  use Ecto.Migration

  def change do
    create table(:time_entries) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, on_delete: :delete_all), null: false
      add :started_at, :naive_datetime, null: false
      add :ended_at, :naive_datetime
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:time_entries, [:business_id])
    create index(:time_entries, [:job_id])
    create index(:time_entries, [:business_id, :job_id])
  end
end
