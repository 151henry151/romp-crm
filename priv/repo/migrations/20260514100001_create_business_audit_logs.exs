defmodule RompCrm.Repo.Migrations.CreateBusinessAuditLogs do
  use Ecto.Migration

  def up do
    create table(:business_audit_logs) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, on_delete: :nilify_all), null: false
      add :source, :string, null: false
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :integer
      add :metadata, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:business_audit_logs, [:business_id, :inserted_at])
    create index(:business_audit_logs, [:actor_user_id, :inserted_at])

    execute """
    INSERT INTO business_audit_logs (business_id, actor_user_id, source, action, entity_type, entity_id, metadata, inserted_at)
    SELECT
      business_id,
      user_id,
      'sms',
      outcome,
      'sms_interaction_log',
      id,
      json_object(
        'legacy', 'sms_interaction_log',
        'twilio_message_sid', COALESCE(twilio_message_sid, ''),
        'phone_normalized', phone_normalized,
        'inbound_body', COALESCE(inbound_body, ''),
        'outbound_body', COALESCE(outbound_body, ''),
        'planned_operations', COALESCE(planned_operations, ''),
        'results_summary', COALESCE(results_summary, '')
      ),
      inserted_at
    FROM sms_interaction_logs
    """
  end

  def down do
    drop table(:business_audit_logs)
  end
end
