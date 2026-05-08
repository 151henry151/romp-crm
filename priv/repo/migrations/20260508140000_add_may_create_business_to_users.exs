defmodule RompCrm.Repo.Migrations.AddMayCreateBusinessToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :may_create_business, :boolean, default: true, null: false
    end
  end
end
