defmodule RompCrm.Repo.Migrations.AddClientIdToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :client_id, references(:clients, on_delete: :nilify_all)
    end

    create index(:jobs, [:client_id])
    create index(:jobs, [:business_id, :client_id])
  end
end
