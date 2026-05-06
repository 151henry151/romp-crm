defmodule JgsCrm.JobsTest do
  use JgsCrm.DataCase

  alias JgsCrm.Jobs

  describe "jobs" do
    alias JgsCrm.Jobs.Job

    import JgsCrm.JobsFixtures

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

    test "list_jobs/0 returns all jobs" do
      job = job_fixture()
      other = job_fixture(%{client_name: "other client"})
      listed = Jobs.list_jobs()
      assert job in listed
      assert other in listed
    end

    test "get_job!/1 returns the job with given id" do
      job = job_fixture()
      assert Jobs.get_job!(job.id) == job
    end

    test "create_job/1 with valid data creates a job" do
      valid_attrs = %{
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
        next_action: "some updated next_action"
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
      assert job.next_action == "some updated next_action"
    end

    test "update_job/2 with invalid data returns error changeset" do
      job = job_fixture()
      assert {:error, %Ecto.Changeset{}} = Jobs.update_job(job, @invalid_attrs)
      assert Jobs.get_job!(job.id).client_name == job.client_name
    end

    test "delete_job/1 deletes the job" do
      job = job_fixture()
      assert {:ok, %Job{}} = Jobs.delete_job(job)
      assert_raise Ecto.NoResultsError, fn -> Jobs.get_job!(job.id) end
    end

    test "change_job/2 returns a job changeset" do
      job = job_fixture()
      assert %Ecto.Changeset{} = Jobs.change_job(job)
    end

    test "find_job_for_sms_update/1 returns job when match hints uniquely" do
      j =
        job_fixture(%{
          client_name: "Angela Brande",
          address: "old",
          work_description: "line repair"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(%{"client_name" => "Angela Brande"})

      assert got.id == j.id
    end

    test "find_job_for_sms_update/1 returns :ambiguous when two jobs tie closely" do
      job_fixture(%{client_name: "Same Client Dup", address: "1 A St"})
      job_fixture(%{client_name: "Same Client Dup", address: "2 B St"})

      assert {:error, :ambiguous} =
               Jobs.find_job_for_sms_update(%{"client_name" => "Same Client Dup"})
    end

    test "find_job_for_sms_update/1 disambiguates duplicate names with address_snippet" do
      job_fixture(%{client_name: "Dup Name", address: "100 Oak Ave"})
      target = job_fixture(%{client_name: "Dup Name", address: "200 Pine Rd"})

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(%{
                 "client_name" => "Dup Name",
                 "address_snippet" => "200 Pine"
               })

      assert got.id == target.id
    end

    test "find_job_for_sms_update/1 returns :no_match when nothing scores enough" do
      job_fixture(%{client_name: "Someone Else"})

      assert {:error, :no_match} =
               Jobs.find_job_for_sms_update(%{"client_name" => "ZZZ Nonexistent Person"})
    end
  end
end
