defmodule RompCrm.Repo.Migrations.BackfillClientsFromJobs do
  use Ecto.Migration

  def up do
    RompCrm.Clients.Backfill.run()
  end

  def down do
    execute "UPDATE jobs SET client_id = NULL"
    execute "DELETE FROM clients"
  end
end
