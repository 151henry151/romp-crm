defmodule RompCrm.Repo.Migrations.AddCustomerCommentsToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :customer_comments, :text
    end
  end
end
