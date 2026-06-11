defmodule RompCrm.Repo.Migrations.CreateCalendarCredentials do
  use Ecto.Migration

  def change do
    create table(:calendar_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :source, :string, null: false
      add :encrypted_credentials, :binary, null: false
      add :status, :string, null: false, default: "connected"
      add :last_sync_error, :text
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:calendar_credentials, [:user_id, :source])
  end
end
