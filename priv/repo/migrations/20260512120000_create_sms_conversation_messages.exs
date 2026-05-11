defmodule RompCrm.Repo.Migrations.CreateSmsConversationMessages do
  use Ecto.Migration

  def change do
    create table(:sms_conversation_messages) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :phone_normalized, :string, null: false
      add :direction, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sms_conversation_messages, [:business_id, :phone_normalized])
  end
end
