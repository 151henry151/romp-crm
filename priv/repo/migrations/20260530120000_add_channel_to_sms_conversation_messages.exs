defmodule RompCrm.Repo.Migrations.AddChannelToSmsConversationMessages do
  use Ecto.Migration

  def change do
    alter table(:sms_conversation_messages) do
      add :channel, :string, null: false, default: "sms"
    end
  end
end
