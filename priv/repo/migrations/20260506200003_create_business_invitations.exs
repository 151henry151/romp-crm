defmodule JgsCrm.Repo.Migrations.CreateBusinessInvitations do
  use Ecto.Migration

  def change do
    create table(:business_invitations) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :invited_by_user_id, references(:users, on_delete: :nilify_all)
      add :email, :string, null: false
      add :token_hash, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:business_invitations, [:token_hash])
    create index(:business_invitations, [:business_id])
    create index(:business_invitations, [:email])

    create unique_index(:business_invitations, [:business_id, :email])
  end
end
