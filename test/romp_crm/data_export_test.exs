defmodule RompCrm.DataExportTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.AccountsFixtures
  alias RompCrm.Businesses
  alias RompCrm.DataExport
  alias RompCrm.DataExportSchedule
  alias RompCrm.JobsFixtures

  describe "compute_next_run_at/2" do
    test "advances by one interval" do
      from = ~U[2026-05-10 12:00:00Z]
      assert ~U[2026-05-11 12:00:00Z] == DataExportSchedule.compute_next_run_at("daily", from)
      assert ~U[2026-05-17 12:00:00Z] == DataExportSchedule.compute_next_run_at("weekly", from)
      assert ~U[2026-06-09 12:00:00Z] == DataExportSchedule.compute_next_run_at("monthly", from)
    end
  end

  describe "build_jobs_csv/1" do
    test "includes only jobs for given business ids" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "Owned Co"})
      other = AccountsFixtures.user_fixture()
      {:ok, other_biz} = Businesses.create_business(other, %{name: "Other"})

      {:ok, j1} =
        RompCrm.Jobs.create_job(%{
          "business_id" => biz.id,
          "client_name" => "A",
          "priority" => "normal",
          "status" => "lead"
        })

      {:ok, _j2} =
        RompCrm.Jobs.create_job(%{
          "business_id" => other_biz.id,
          "client_name" => "Secret",
          "priority" => "normal",
          "status" => "lead"
        })

      csv = DataExport.build_jobs_csv([biz.id])
      assert csv =~ "A"
      refute csv =~ "Secret"
      assert csv =~ to_string(j1.id)
    end
  end

  describe "build_audit_log_csv/1" do
    test "includes audit rows for owned business ids" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "Audit Co"})

      RompCrm.BusinessAuditLogs.record(%{
        business_id: biz.id,
        actor_user_id: owner.id,
        source: "web",
        action: "jobs.create",
        entity_type: "jobs",
        entity_id: 42,
        metadata: %{}
      })

      csv = DataExport.build_audit_log_csv([biz.id])
      assert csv =~ "jobs.create"
      assert csv =~ owner.email
      assert csv =~ "42"
    end
  end

  describe "build_time_log_csv/1" do
    test "includes job time rows for business" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "T Co"})
      job = JobsFixtures.job_fixture(%{business_id: biz.id, client_name: "Client Z"})

      {:ok, _} =
        RompCrm.TimeTracking.create_time_entry(%{
          business_id: biz.id,
          job_id: job.id,
          started_at: ~N[2026-05-11 09:00:00],
          ended_at: ~N[2026-05-11 10:00:00]
        })

      csv = DataExport.build_time_log_csv([biz.id])
      assert csv =~ "job_time"
      assert csv =~ "Client Z"
    end
  end
end
