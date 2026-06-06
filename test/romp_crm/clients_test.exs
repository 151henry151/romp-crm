defmodule RompCrm.ClientsTest do
  use RompCrm.DataCase

  alias RompCrm.Clients
  alias RompCrm.Clients.Client
  alias RompCrm.Jobs

  import RompCrm.JobsFixtures

  test "create_client/1 and list_clients/1" do
    b = business_fixture()

    assert {:ok, %Client{} = client} =
             Clients.create_client(%{
               business_id: b.id,
               client_name: "Ada Lovelace",
               phone: "+18025550101"
             })

    assert client.client_name == "Ada Lovelace"
    listed = Clients.list_clients(b.id)
    assert Enum.any?(listed, &(&1.id == client.id))
  end

  test "finalize_job_client_link/2 creates client from job contact" do
    b = business_fixture()

    assert {:ok, job} =
             Jobs.create_job(%{
               business_id: b.id,
               client_name: "Bob Builder",
               phone: "+18025550102",
               priority: :normal,
               status: :lead
             })

    assert is_nil(job.client_id)

    assert {:ok, linked} = Clients.finalize_job_client_link(job, Map.from_struct(job))
    assert linked.client_id
    assert Clients.get_client(linked.client_id, b.id).client_name == "Bob Builder"
  end

  test "update_client_and_sync_jobs/2 copies contact onto linked jobs" do
    b = business_fixture()

    assert {:ok, client} =
             Clients.create_client(%{business_id: b.id, client_name: "Carol", phone: "+18025550103"})

    assert {:ok, job} =
             Jobs.create_job(%{
               business_id: b.id,
               client_id: client.id,
               client_name: client.client_name,
               phone: client.phone,
               priority: :normal,
               status: :lead
             })

    assert {:ok, _} =
             Clients.update_client_and_sync_jobs(client, %{"phone" => "+18025550199"})

    reloaded = Jobs.get_job!(job.id, b.id)
    assert reloaded.phone == "+18025550199"
  end

  test "delete_client_and_jobs/1 removes linked jobs" do
    b = business_fixture()

    assert {:ok, client} =
             Clients.create_client(%{business_id: b.id, client_name: "Dan", phone: "+18025550104"})

    assert {:ok, job} =
             Jobs.create_job(%{
               business_id: b.id,
               client_id: client.id,
               client_name: client.client_name,
               priority: :normal,
               status: :lead
             })

    assert {:ok, _} = Clients.delete_client_and_jobs(client)
    assert Clients.get_client(client.id, b.id) == nil
    assert Jobs.get_job(job.id, b.id) == nil
  end
end
