defmodule RompCrm.Repo.Migrations.CreateBookingEscalationsAndSchedulingMemories do
  use Ecto.Migration

  def change do
    create table(:booking_escalations) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :technician_user_id, references(:users, on_delete: :nilify_all), null: false
      add :booking_link_id, references(:booking_links, on_delete: :nilify_all)
      add :client_id, references(:clients, on_delete: :nilify_all)
      add :client_phone_normalized, :string, null: false
      add :client_name, :string, null: false, default: ""
      add :question_text, :text, null: false
      add :status, :string, null: false, default: "pending_contractor"
      add :contractor_answer, :text
      add :memory_candidate, :text
      add :memory_saved, :boolean, null: false, default: false
      add :client_relayed_at, :utc_datetime
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:booking_escalations, [:business_id, :status])
    create index(:booking_escalations, [:technician_user_id, :status])

    create table(:scheduling_memories) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :topic, :string, null: false
      add :answer_text, :text, null: false
      add :source_escalation_id, references(:booking_escalations, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scheduling_memories, [:business_id])
  end
end
