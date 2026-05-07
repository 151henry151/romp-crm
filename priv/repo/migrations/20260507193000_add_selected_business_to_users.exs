defmodule RompCrm.Repo.Migrations.AddSelectedBusinessToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :selected_business_id, references(:businesses, on_delete: :nilify_all)
    end

    create index(:users, [:selected_business_id])
  end
end
