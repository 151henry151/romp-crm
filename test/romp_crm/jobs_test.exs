defmodule RompCrm.JobsTest do
  use RompCrm.DataCase

  alias RompCrm.Jobs

  describe "jobs" do
    alias RompCrm.Jobs.Job

    import RompCrm.JobsFixtures

    @invalid_attrs %{
      priority: nil,
      status: nil,
      address: nil,
      client_name: nil,
      phone: nil,
      work_description: nil,
      referred_by: nil,
      notes: nil,
      next_action: nil
    }

    test "list_jobs/1 returns jobs for the business" do
      b = business_fixture()
      job = job_fixture(%{business_id: b.id})
      other = job_fixture(%{client_name: "other client", business_id: b.id})
      listed = Jobs.list_jobs(b.id)
      assert job in listed
      assert other in listed
    end

    test "get_job!/2 returns the job with given id for that business" do
      job = job_fixture()
      assert Jobs.get_job!(job.id, job.business_id) == job
    end

    test "create_job/1 with valid data creates a job" do
      b = business_fixture()

      valid_attrs = %{
        business_id: b.id,
        priority: :high,
        status: :pending,
        address: "some address",
        client_name: "some client_name",
        phone: "some phone",
        work_description: "some work_description",
        referred_by: "some referred_by",
        notes: "some notes",
        next_action: "some next_action"
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs)
      assert job.priority == :high
      assert job.status == :pending
      assert job.address == "some address"
      assert job.client_name == "some client_name"
      assert job.phone == "some phone"
      assert job.work_description == "some work_description"
      assert job.referred_by == "some referred_by"
      assert job.notes == "some notes"
      assert job.next_action == "some next_action"
    end

    test "create_job/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Jobs.create_job(@invalid_attrs)
    end

    test "update_job/2 with valid data updates the job" do
      job = job_fixture()

      update_attrs = %{
        priority: :normal,
        status: :in_progress,
        address: "some updated address",
        client_name: "some updated client_name",
        phone: "some updated phone",
        work_description: "some updated work_description",
        referred_by: "some updated referred_by",
        notes: "some updated notes",
        next_action: "some next_action"
      }

      assert {:ok, %Job{} = job} = Jobs.update_job(job, update_attrs)
      assert job.priority == :normal
      assert job.status == :in_progress
      assert job.address == "some updated address"
      assert job.client_name == "some updated client_name"
      assert job.phone == "some updated phone"
      assert job.work_description == "some updated work_description"
      assert job.referred_by == "some updated referred_by"
      assert job.notes == "some updated notes"
      assert job.next_action == "some next_action"
    end

    test "update_job/2 appends work_items without id onto existing line items" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Celeste",
                 "priority" => "normal",
                 "status" => "pending",
                 "work_description" => "Water heater",
                 "work_items" => [
                   %{"title" => "Replace water heater"},
                   %{"title" => "Reconnect lines"}
                 ]
               })

      job = Jobs.get_job!(job.id, b.id)
      assert length(job.work_items) == 2

      assert {:ok, %Job{} = job2} =
               Jobs.update_job(job, %{
                 "work_description" => "Water heater; kitchen faucet on same visit",
                 "work_items" => [%{"title" => "Replace kitchen sink faucet"}]
               })

      job2 = Jobs.get_job!(job2.id, b.id)
      titles = Enum.map(job2.work_items, & &1.title)
      assert length(job2.work_items) == 3
      assert "Replace kitchen sink faucet" in titles
      assert "Replace water heater" in titles
      assert "Reconnect lines" in titles
      assert job2.work_description == "Water heater; kitchen faucet on same visit"
    end

    test "delete_job/1 deletes the job" do
      job = job_fixture()
      assert {:ok, %Job{}} = Jobs.delete_job(job)

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(job.id, job.business_id)
      end
    end

    test "change_job/2 returns a job changeset" do
      job = job_fixture()
      assert %Ecto.Changeset{} = Jobs.change_job(job)
    end

    test "find_job_for_sms_update/2 returns job when match hints uniquely" do
      b = business_fixture()

      j =
        job_fixture(%{
          business_id: b.id,
          client_name: "Angela Brande",
          address: "old",
          work_description: "line repair"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(%{"client_name" => "Angela Brande"}, b.id)

      assert got.id == j.id
    end

    test "find_job_for_sms_update/2 returns :ambiguous when two jobs tie closely" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Same Client Dup", address: "1 A St"})
      job_fixture(%{business_id: b.id, client_name: "Same Client Dup", address: "2 B St"})

      assert {:error, :ambiguous} =
               Jobs.find_job_for_sms_update(%{"client_name" => "Same Client Dup"}, b.id)
    end

    test "find_job_for_sms_update/2 disambiguates duplicate names with address_snippet" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Dup Name", address: "100 Oak Ave"})
      target = job_fixture(%{business_id: b.id, client_name: "Dup Name", address: "200 Pine Rd"})

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(
                 %{
                   "client_name" => "Dup Name",
                   "address_snippet" => "200 Pine"
                 },
                 b.id
               )

      assert got.id == target.id
    end

    test "find_job_for_sms_update/2 returns :no_match when nothing scores enough" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Someone Else"})

      assert {:error, :no_match} =
               Jobs.find_job_for_sms_update(%{"client_name" => "ZZZ Nonexistent Person"}, b.id)
    end

    test "find_job_for_sms_update/2 matches by work_description_snippet when it is the only strong hint" do
      b = business_fixture()

      j =
        job_fixture(%{
          business_id: b.id,
          client_name: "Bud Reed",
          address: "Evergreen Lane",
          work_description: "Water shutoff"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(
                 %{"work_description_snippet" => "water shutoff"},
                 b.id
               )

      assert got.id == j.id
    end

    test "find_job_for_sms_update/2 returns :ambiguous when two jobs share the same work phrase" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Ann", work_description: "Water shutoff"})
      job_fixture(%{business_id: b.id, client_name: "Bob", work_description: "Water shutoff"})

      assert {:error, :ambiguous} =
               Jobs.find_job_for_sms_update(
                 %{"work_description_snippet" => "water shutoff"},
                 b.id
               )
    end

    test "find_job_for_sms_update/2 accepts address_snippet alone when exactly one job matches" do
      b = business_fixture()

      j =
        job_fixture(%{
          business_id: b.id,
          client_name: "Corner Case",
          address: "999 Zephyr Road"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(%{"address_snippet" => "Zephyr"}, b.id)

      assert got.id == j.id
    end
  end
end
