defmodule JgsCrm.JobsTest do
  use JgsCrm.DataCase

  alias JgsCrm.Jobs

  describe "jobs" do
    alias JgsCrm.Jobs.Job

    import JgsCrm.AccountsFixtures, only: [user_scope_fixture: 0]
    import JgsCrm.JobsFixtures

    @invalid_attrs %{priority: nil, status: nil, address: nil, client_name: nil, phone: nil, work_description: nil, referred_by: nil, notes: nil, next_action: nil}

    test "list_jobs/1 returns all scoped jobs" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      job = job_fixture(scope)
      other_job = job_fixture(other_scope)
      assert Jobs.list_jobs(scope) == [job]
      assert Jobs.list_jobs(other_scope) == [other_job]
    end

    test "get_job!/2 returns the job with given id" do
      scope = user_scope_fixture()
      job = job_fixture(scope)
      other_scope = user_scope_fixture()
      assert Jobs.get_job!(scope, job.id) == job
      assert_raise Ecto.NoResultsError, fn -> Jobs.get_job!(other_scope, job.id) end
    end

    test "create_job/2 with valid data creates a job" do
      valid_attrs = %{priority: "some priority", status: "some status", address: "some address", client_name: "some client_name", phone: "some phone", work_description: "some work_description", referred_by: "some referred_by", notes: "some notes", next_action: "some next_action"}
      scope = user_scope_fixture()

      assert {:ok, %Job{} = job} = Jobs.create_job(scope, valid_attrs)
      assert job.priority == "some priority"
      assert job.status == "some status"
      assert job.address == "some address"
      assert job.client_name == "some client_name"
      assert job.phone == "some phone"
      assert job.work_description == "some work_description"
      assert job.referred_by == "some referred_by"
      assert job.notes == "some notes"
      assert job.next_action == "some next_action"
      assert job.user_id == scope.user.id
    end

    test "create_job/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Jobs.create_job(scope, @invalid_attrs)
    end

    test "update_job/3 with valid data updates the job" do
      scope = user_scope_fixture()
      job = job_fixture(scope)
      update_attrs = %{priority: "some updated priority", status: "some updated status", address: "some updated address", client_name: "some updated client_name", phone: "some updated phone", work_description: "some updated work_description", referred_by: "some updated referred_by", notes: "some updated notes", next_action: "some updated next_action"}

      assert {:ok, %Job{} = job} = Jobs.update_job(scope, job, update_attrs)
      assert job.priority == "some updated priority"
      assert job.status == "some updated status"
      assert job.address == "some updated address"
      assert job.client_name == "some updated client_name"
      assert job.phone == "some updated phone"
      assert job.work_description == "some updated work_description"
      assert job.referred_by == "some updated referred_by"
      assert job.notes == "some updated notes"
      assert job.next_action == "some updated next_action"
    end

    test "update_job/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      job = job_fixture(scope)

      assert_raise MatchError, fn ->
        Jobs.update_job(other_scope, job, %{})
      end
    end

    test "update_job/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      job = job_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Jobs.update_job(scope, job, @invalid_attrs)
      assert job == Jobs.get_job!(scope, job.id)
    end

    test "delete_job/2 deletes the job" do
      scope = user_scope_fixture()
      job = job_fixture(scope)
      assert {:ok, %Job{}} = Jobs.delete_job(scope, job)
      assert_raise Ecto.NoResultsError, fn -> Jobs.get_job!(scope, job.id) end
    end

    test "delete_job/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      job = job_fixture(scope)
      assert_raise MatchError, fn -> Jobs.delete_job(other_scope, job) end
    end

    test "change_job/2 returns a job changeset" do
      scope = user_scope_fixture()
      job = job_fixture(scope)
      assert %Ecto.Changeset{} = Jobs.change_job(scope, job)
    end
  end
end
