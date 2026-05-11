defmodule RompCrm.Repo.Migrations.CreateEmployees do
  use Ecto.Migration

  def change do
    create table(:employees) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :phone, :string
      add :email, :string
      add :title, :string
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:employees, [:business_id])
    create index(:employees, [:business_id, :name])
  end
end
