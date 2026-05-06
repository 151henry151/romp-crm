defmodule JgsCrm.Repo.Migrations.CreateBusinessMemberships do
  use Ecto.Migration

  def change do
    create table(:business_memberships) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:business_memberships, [:business_id, :user_id])
    create index(:business_memberships, [:user_id])
  end
end
