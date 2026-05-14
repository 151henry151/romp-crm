defmodule RompCrm.Repo.Migrations.AddSmsAssistantIntroCompletedAtToUsers do
  use Ecto.Migration

  import Ecto.Query

  alias RompCrm.Accounts.User
  alias RompCrm.Repo

  def up do
    alter table(:users) do
      add :sms_assistant_intro_completed_at, :utc_datetime
    end

    flush()

    now = DateTime.utc_now(:second)
    Repo.update_all(from(u in User), set: [sms_assistant_intro_completed_at: now])
  end

  def down do
    alter table(:users) do
      remove :sms_assistant_intro_completed_at
    end
  end
end
