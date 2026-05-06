defmodule JgsCrm.Repo.Migrations.AddBusinessIdToJobsAndBackfill do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:jobs) do
      add :business_id, references(:businesses, on_delete: :delete_all)
    end

    flush()

    repo = JgsCrm.Repo

    {:ok, business} =
      %JgsCrm.Businesses.Business{}
      |> JgsCrm.Businesses.Business.changeset(%{name: "Default workspace"})
      |> repo.insert()

    bid = business.id

    repo.update_all(from(j in JgsCrm.Jobs.Job), set: [business_id: bid])

    users = repo.all(JgsCrm.Accounts.User)

    Enum.each(users, fn user ->
      %JgsCrm.Businesses.BusinessMembership{}
      |> JgsCrm.Businesses.BusinessMembership.changeset(%{
        business_id: bid,
        user_id: user.id,
        role: :owner
      })
      |> repo.insert!()
    end)

    :ok
  end

  def down do
    alter table(:jobs) do
      remove :business_id
    end
  end
end
