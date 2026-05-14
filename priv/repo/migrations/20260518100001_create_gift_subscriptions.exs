defmodule RompCrm.Repo.Migrations.CreateGiftSubscriptions do
  use Ecto.Migration

  def change do
    create table(:gift_subscriptions) do
      add :token, :string, null: false
      add :recipient_email, :string, null: false
      add :duration_days, :integer, null: false
      add :admin_message, :text
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :redeemed_at, :utc_datetime
      add :redeemed_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gift_subscriptions, [:token])
    create index(:gift_subscriptions, [:recipient_email])
  end
end
