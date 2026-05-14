defmodule RompCrm.Repo.Migrations.AddDataExportSelectionJsonToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :data_export_kinds_json, :text
      add :data_export_business_ids_json, :text
    end
  end
end
