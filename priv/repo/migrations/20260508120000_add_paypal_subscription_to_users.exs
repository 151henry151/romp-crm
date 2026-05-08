defmodule RompCrm.Repo.Migrations.AddPaypalSubscriptionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :paypal_subscription_id, :string
      add :paypal_plan_id, :string
      # Default `active` keeps existing users and self-hosted installs working without PayPal.
      add :subscription_status, :string, null: false, default: "active"
    end

    create unique_index(:users, [:paypal_subscription_id],
             where: "paypal_subscription_id IS NOT NULL",
             name: :users_paypal_subscription_id_unique
           )

    create index(:users, [:subscription_status])
  end
end
