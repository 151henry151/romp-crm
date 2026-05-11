defmodule RompCrm.Repo.Migrations.CreateEmployeeTimeEntries do
  use Ecto.Migration

  def change do
    create table(:employee_time_entries) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :employee_id, references(:employees, on_delete: :delete_all), null: false
      add :clocked_in_at, :naive_datetime, null: false
      add :clocked_out_at, :naive_datetime
      add :lunch_start_at, :naive_datetime
      add :lunch_end_at, :naive_datetime
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:employee_time_entries, [:business_id])
    create index(:employee_time_entries, [:employee_id])
    create index(:employee_time_entries, [:business_id, :employee_id])
  end
end
