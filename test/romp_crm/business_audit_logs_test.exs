defmodule RompCrm.BusinessAuditLogsTest do
  use RompCrm.DataCase

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.JobsFixtures

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  test "recent_deleted_jobs_snapshot/2 returns deleted job rows for AI context" do
    user = user_fixture()
    biz = business_fixture()
    job = JobsFixtures.job_fixture(%{business_id: biz.id, client_name: "Website photos"})

    :ok =
      BusinessAuditLogs.record(%{
        business_id: biz.id,
        actor_user_id: user.id,
        source: "web",
        action: "jobs.delete",
        entity_type: "jobs",
        entity_id: job.id,
        metadata: %{
          client_name: job.client_name,
          job_id: job.id,
          changes: [%{type: "job_deleted", job_id: job.id, client_name: job.client_name}]
        }
      })

    [row] = BusinessAuditLogs.recent_deleted_jobs_snapshot(biz.id)
    assert row["job_id"] == job.id
    assert row["client_name"] == "Website photos"
    assert is_binary(row["deleted_at"])
  end
end
