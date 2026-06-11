defmodule RompCrm.Repo.Migrations.AddSchedulingPrefsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :scheduling_prefs_json, :text
    end
  end
end
