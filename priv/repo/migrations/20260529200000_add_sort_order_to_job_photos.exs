defmodule RompCrm.Repo.Migrations.AddSortOrderToJobPhotos do
  use Ecto.Migration

  def change do
    alter table(:job_photos) do
      add :sort_order, :integer, null: false, default: 0
    end

    execute(
      "UPDATE job_photos SET sort_order = id",
      "UPDATE job_photos SET sort_order = 0"
    )
  end
end
