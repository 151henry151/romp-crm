defmodule RompCrm.Repo.Migrations.CreateClients do
  use Ecto.Migration

  def change do
    create table(:clients) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false

      add :client_name, :string, null: false, default: ""
      add :phone, :string
      add :client_email, :string
      add :address, :text
      add :address_line1, :string
      add :address_line2, :string
      add :city, :string
      add :state, :string
      add :postal_code, :string
      add :billing_address_different, :boolean, null: false, default: false
      add :billing_address_line1, :string
      add :billing_address_line2, :string
      add :billing_city, :string
      add :billing_state, :string
      add :billing_postal_code, :string
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:clients, [:business_id])
    create index(:clients, [:business_id, :client_name])
  end
end
