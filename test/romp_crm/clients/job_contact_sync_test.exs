defmodule RompCrm.Clients.JobContactSyncTest do
  use RompCrm.DataCase

  alias RompCrm.Clients
  alias RompCrm.Jobs

  import RompCrm.JobsFixtures

  test "update_job_contact_and_sync/2 writes phone onto client and survives merge-on-read" do
    b = business_fixture()

    assert {:ok, client} =
             Clients.create_client(%{
               business_id: b.id,
               client_name: "Will Nash",
               address_line1: "33 South Street"
             })

    assert {:ok, job} =
             Jobs.create_job(%{
               business_id: b.id,
               client_id: client.id,
               client_name: client.client_name,
               address_line1: client.address_line1,
               phone: nil,
               priority: :normal,
               status: :pending
             })

    # Empty client phone overlays blank onto the job for display/AI.
    assert is_nil(Jobs.get_job!(job.id, b.id).phone) or Jobs.get_job!(job.id, b.id).phone == ""

    assert {:ok, updated} =
             Clients.update_job_contact_and_sync(job, %{"phone" => "8029899322"})

    assert updated.phone in ["8029899322", "+18029899322", "18029899322"]

    client = Clients.get_client!(client.id, b.id)
    assert client.phone in ["8029899322", "+18029899322", "18029899322"]

    # merge_client_onto_job must keep the phone visible after sync
    assert Jobs.get_job!(job.id, b.id).phone == client.phone
  end
end
