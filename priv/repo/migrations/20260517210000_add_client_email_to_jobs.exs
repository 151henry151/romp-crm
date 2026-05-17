defmodule RompCrm.Repo.Migrations.AddClientEmailToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :client_email, :string
    end
  end
end
