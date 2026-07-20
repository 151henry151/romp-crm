defmodule RompCrm.Clients.JobNotesMergeTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.Clients
  alias RompCrm.Jobs

  import RompCrm.JobsFixtures

  test "job notes survive merge-on-read when linked client has different notes" do
    b = business_fixture()

    assert {:ok, client} =
             Clients.create_client(%{
               business_id: b.id,
               client_name: "Carolyn Brewer",
               notes: "Client-level CRM notes"
             })

    assert {:ok, job} =
             Jobs.create_job(%{
               business_id: b.id,
               client_id: client.id,
               client_name: client.client_name,
               notes: "Job-site notes",
               priority: :normal,
               status: :pending
             })

    assert {:ok, _} = Jobs.update_job(job, %{"notes" => "Updated job notes from expand edit"})

    loaded = Jobs.get_job!(job.id, b.id)
    assert loaded.notes == "Updated job notes from expand edit"

    client = Clients.get_client!(client.id, b.id)
    assert client.notes == "Client-level CRM notes"
  end
end
