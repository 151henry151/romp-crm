defmodule RompCrm.Repo.Migrations.AddThreadKindToSmsConversationMessages do
  use Ecto.Migration

  def change do
    alter table(:sms_conversation_messages) do
      add :thread_kind, :string, null: false, default: "contractor"
    end

    create index(:sms_conversation_messages, [:business_id, :thread_kind, :phone_normalized])
  end
end
