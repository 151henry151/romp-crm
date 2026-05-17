defmodule RompCrm.Repo.Migrations.AddEntryKindsToEmployeeTimeEntries do
  use Ecto.Migration

  def change do
    alter table(:employee_time_entries) do
      add :clock_in_kind, :string
      add :clock_out_kind, :string
    end
  end
end
