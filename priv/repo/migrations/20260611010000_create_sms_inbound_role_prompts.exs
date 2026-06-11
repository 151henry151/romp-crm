defmodule RompCrm.Repo.Migrations.CreateSmsInboundRolePrompts do
  use Ecto.Migration

  def change do
    create table(:sms_inbound_role_prompts) do
      add :phone_normalized, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :booking_business_names_json, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sms_inbound_role_prompts, [:phone_normalized])
  end
end
