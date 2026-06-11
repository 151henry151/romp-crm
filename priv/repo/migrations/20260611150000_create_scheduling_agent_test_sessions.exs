defmodule RompCrm.Repo.Migrations.CreateSchedulingAgentTestSessions do
  use Ecto.Migration

  def change do
    create table(:scheduling_agent_test_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :state_json, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scheduling_agent_test_sessions, [:user_id, :business_id])
  end
end
