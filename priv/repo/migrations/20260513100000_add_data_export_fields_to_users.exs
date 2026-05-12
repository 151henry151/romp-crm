defmodule RompCrm.Repo.Migrations.AddDataExportFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :data_export_schedule, :string, null: false, default: "none"
      add :data_export_next_run_at, :utc_datetime
      add :data_export_last_sent_at, :utc_datetime
    end

    create index(:users, [:data_export_schedule, :data_export_next_run_at])
  end
end
