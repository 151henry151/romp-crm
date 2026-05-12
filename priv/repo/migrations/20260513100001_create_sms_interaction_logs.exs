defmodule RompCrm.Repo.Migrations.CreateSmsInteractionLogs do
  use Ecto.Migration

  def change do
    create table(:sms_interaction_logs) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :twilio_message_sid, :string
      add :phone_normalized, :string, null: false, default: ""
      add :outcome, :string, null: false, default: "unknown"
      add :inbound_body, :text
      add :outbound_body, :text
      add :planned_operations, :text
      add :results_summary, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:sms_interaction_logs, [:business_id, :inserted_at])
    create index(:sms_interaction_logs, [:user_id, :inserted_at])
  end
end
