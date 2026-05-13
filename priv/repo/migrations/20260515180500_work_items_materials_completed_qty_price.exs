defmodule RompCrm.Repo.Migrations.WorkItemsMaterialsCompletedQtyPrice do
  use Ecto.Migration

  def change do
    alter table(:job_work_items) do
      add :completed, :boolean, null: false, default: false
    end

    alter table(:job_materials) do
      add :completed, :boolean, null: false, default: false
      add :quantity, :float, null: false, default: 1.0
      add :unit_price, :float
    end
  end
end
