defmodule RompCrm.Repo.Migrations.AddBusinessIdToJobsAndBackfill do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:jobs) do
      add :business_id, references(:businesses, on_delete: :delete_all)
    end

    flush()

    repo = RompCrm.Repo

    {:ok, business} =
      %RompCrm.Businesses.Business{}
      |> RompCrm.Businesses.Business.changeset(%{name: "Default workspace"})
      |> repo.insert()

    bid = business.id

    repo.update_all(from(j in RompCrm.Jobs.Job), set: [business_id: bid])

    users = repo.query!("SELECT id FROM users").rows |> Enum.map(fn [id] -> %{id: id} end)

    Enum.each(users, fn user ->
      %RompCrm.Businesses.BusinessMembership{}
      |> RompCrm.Businesses.BusinessMembership.changeset(%{
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
