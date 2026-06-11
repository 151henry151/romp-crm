defmodule RompCrm.Repo.Migrations.CreateSchedulingPlaybookAndSetup do
  use Ecto.Migration

  alias RompCrm.Repo
  alias RompCrm.Accounts.User
  import Ecto.Query

  def up do
    alter table(:users) do
      add :scheduling_setup_completed_at, :utc_datetime
    end

    flush()

    now = DateTime.utc_now(:second)

    Repo.update_all(
      from(u in User, where: is_nil(u.scheduling_setup_completed_at)),
      set: [scheduling_setup_completed_at: now]
    )

    create table(:scheduling_playbook_rules) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :technician_user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :config, :map, null: false, default: %{}
      add :source_text, :text
      add :active, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:scheduling_playbook_rules, [:business_id])
    create index(:scheduling_playbook_rules, [:technician_user_id])
    create index(:scheduling_playbook_rules, [:business_id, :technician_user_id, :kind])

    create table(:sms_scheduling_setup_sessions) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :phone_normalized, :string, null: false
      add :phase, :string, null: false, default: "awaiting_structured"
      add :held_intent_json, :text
      add :structured_answers_json, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sms_scheduling_setup_sessions, [:business_id, :phone_normalized])

    create table(:booking_slot_approvals) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :technician_user_id, references(:users, on_delete: :delete_all), null: false
      add :booking_link_id, references(:booking_links, on_delete: :delete_all), null: false
      add :client_phone_normalized, :string, null: false
      add :local_offerings_json, :text, null: false
      add :open_slots_json, :text
      add :customer_pending_reply, :text
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:booking_slot_approvals, [:business_id, :technician_user_id, :status])
    create index(:booking_slot_approvals, [:booking_link_id])
  end

  def down do
    drop table(:booking_slot_approvals)
    drop table(:sms_scheduling_setup_sessions)
    drop table(:scheduling_playbook_rules)

    alter table(:users) do
      remove :scheduling_setup_completed_at
    end
  end
end
