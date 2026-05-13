defmodule RompCrm.Repo.Migrations.SmsReminderPrefsAndJobReminderLogs do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :sms_reminder_prefs_json, :text
    end

    create table(:job_reminder_send_logs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :job_id, references(:jobs, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :anchor_on, :date, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:job_reminder_send_logs, [:user_id, :job_id, :kind, :anchor_on],
             name: :job_reminder_send_logs_user_job_kind_anchor_unique
           )

    create index(:job_reminder_send_logs, [:user_id])
    create index(:job_reminder_send_logs, [:job_id])
  end
end
