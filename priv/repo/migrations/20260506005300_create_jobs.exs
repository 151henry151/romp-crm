defmodule RompCrm.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs) do
      add :client_name, :string, null: false
      add :address, :string
      add :phone, :string
      add :work_description, :text
      add :priority, :string, null: false, default: "normal"
      add :status, :string, null: false, default: "lead"
      add :referred_by, :string
      add :notes, :text
      add :next_action, :string

      timestamps(type: :utc_datetime)
    end
  end
end
