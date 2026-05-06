defmodule JgsCrm.Repo.Migrations.AddPhoneAndSmsBusinessToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone, :string
      add :phone_normalized, :string
      add :sms_business_id, references(:businesses, on_delete: :nilify_all)
    end

    create unique_index(:users, [:phone_normalized],
             where: "phone_normalized IS NOT NULL AND phone_normalized != ''"
           )
  end
end
