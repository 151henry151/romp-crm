defmodule RompCrm.Repo.Migrations.RemindersAndUserSmsReminders do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :sms_reminders_enabled, :boolean, null: false, default: false
    end

    create table(:reminders) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, on_delete: :nilify_all)
      add :body, :text, null: false
      add :fire_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "pending"
      add :source, :string
      add :metadata_json, :text

      timestamps(type: :utc_datetime)
    end

    create index(:reminders, [:user_id])
    create index(:reminders, [:business_id])
    create index(:reminders, [:fire_at])
    create index(:reminders, [:status])
  end
end
