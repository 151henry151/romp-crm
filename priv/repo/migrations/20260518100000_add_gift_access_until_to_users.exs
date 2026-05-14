defmodule RompCrm.Repo.Migrations.AddGiftAccessUntilToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :gift_access_until, :utc_datetime
    end
  end
end
