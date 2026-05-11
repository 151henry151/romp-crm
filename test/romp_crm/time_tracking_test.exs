defmodule RompCrm.TimeTrackingTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.TimeTracking
  alias RompCrm.TimeTracking.TimeEntry

  import RompCrm.JobsFixtures
  import RompCrm.TimeTrackingFixtures

  setup do
    biz = business_fixture()
    job = job_fixture(%{business_id: biz.id, client_name: "Angela Bertrand"})
    {:ok, biz: biz, job: job}
  end

  describe "list_time_entries/1" do
    test "returns entries for business ordered newest first", %{biz: biz, job: job} do
      e1 =
        time_entry_fixture(%{
          job_id: job.id,
          business_id: biz.id,
          started_at: ~N[2026-05-11 08:00:00]
        })

      e2 =
        time_entry_fixture(%{
          job_id: job.id,
          business_id: biz.id,
          started_at: ~N[2026-05-11 13:00:00]
        })

      entries = TimeTracking.list_time_entries(biz.id)
      assert length(entries) == 2
      assert hd(entries).id == e2.id
      assert List.last(entries).id == e1.id
    end

    test "preloads job association", %{biz: biz, job: job} do
      time_entry_fixture(%{job_id: job.id, business_id: biz.id})
      [entry] = TimeTracking.list_time_entries(biz.id)
      assert entry.job.client_name == "Angela Bertrand"
    end

    test "does not return entries from other businesses", %{biz: biz, job: job} do
      other_biz = business_fixture()
      other_job = job_fixture(%{business_id: other_biz.id})
      time_entry_fixture(%{job_id: job.id, business_id: biz.id})
      time_entry_fixture(%{job_id: other_job.id, business_id: other_biz.id})

      assert length(TimeTracking.list_time_entries(biz.id)) == 1
    end
  end

  describe "list_time_entries_for_job/2" do
    test "returns only entries for that job", %{biz: biz, job: job} do
      job2 = job_fixture(%{business_id: biz.id, client_name: "Dave Wohl"})
      e1 = time_entry_fixture(%{job_id: job.id, business_id: biz.id})
      _e2 = time_entry_fixture(%{job_id: job2.id, business_id: biz.id})

      entries = TimeTracking.list_time_entries_for_job(job.id, biz.id)
      assert length(entries) == 1
      assert hd(entries).id == e1.id
    end
  end

  describe "get_open_entry_for_job/2" do
    test "returns open entry when one exists", %{biz: biz, job: job} do
      open =
        time_entry_fixture(%{
          job_id: job.id,
          business_id: biz.id,
          started_at: ~N[2026-05-11 08:00:00]
        })

      result = TimeTracking.get_open_entry_for_job(job.id, biz.id)
      assert result.id == open.id
    end

    test "returns nil when no open entry", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00],
        ended_at: ~N[2026-05-11 14:00:00]
      })

      assert TimeTracking.get_open_entry_for_job(job.id, biz.id) == nil
    end
  end

  describe "create_time_entry/1" do
    test "creates entry with required fields", %{biz: biz, job: job} do
      assert {:ok, %TimeEntry{} = entry} =
               TimeTracking.create_time_entry(%{
                 business_id: biz.id,
                 job_id: job.id,
                 started_at: ~N[2026-05-11 08:00:00]
               })

      assert entry.business_id == biz.id
      assert entry.job_id == job.id
      assert entry.started_at == ~N[2026-05-11 08:00:00]
      assert entry.ended_at == nil
    end

    test "returns error changeset when missing required fields", %{biz: biz} do
      assert {:error, changeset} = TimeTracking.create_time_entry(%{business_id: biz.id})
      assert changeset.errors[:job_id] != nil
      assert changeset.errors[:started_at] != nil
    end
  end

  describe "update_time_entry/2" do
    test "sets ended_at to close an open entry", %{biz: biz, job: job} do
      entry = time_entry_fixture(%{job_id: job.id, business_id: biz.id})

      assert {:ok, updated} =
               TimeTracking.update_time_entry(entry, %{ended_at: ~N[2026-05-11 14:00:00]})

      assert updated.ended_at == ~N[2026-05-11 14:00:00]
    end
  end

  describe "delete_time_entry/1" do
    test "deletes the entry", %{biz: biz, job: job} do
      entry = time_entry_fixture(%{job_id: job.id, business_id: biz.id})
      assert {:ok, _} = TimeTracking.delete_time_entry(entry)
      assert TimeTracking.list_time_entries_for_job(job.id, biz.id) == []
    end
  end

  describe "total_minutes_for_job/2" do
    test "sums completed entries", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00],
        ended_at: ~N[2026-05-11 10:00:00]
      })

      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 13:00:00],
        ended_at: ~N[2026-05-11 14:30:00]
      })

      assert TimeTracking.total_minutes_for_job(job.id, biz.id) == 210
    end

    test "ignores open entries", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00]
      })

      assert TimeTracking.total_minutes_for_job(job.id, biz.id) == 0
    end

    test "returns 0 when no entries", %{biz: biz, job: job} do
      assert TimeTracking.total_minutes_for_job(job.id, biz.id) == 0
    end
  end

  describe "format_total_for_job/2" do
    test "formats hours and minutes", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00],
        ended_at: ~N[2026-05-11 14:30:00]
      })

      assert TimeTracking.format_total_for_job(job.id, biz.id) == "6h 30m"
    end

    test "formats minutes only when under an hour", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00],
        ended_at: ~N[2026-05-11 08:45:00]
      })

      assert TimeTracking.format_total_for_job(job.id, biz.id) == "45m"
    end

    test "returns '0m' when no entries", %{biz: biz, job: job} do
      assert TimeTracking.format_total_for_job(job.id, biz.id) == "0m"
    end
  end

  describe "snapshot_for_sms_ai/1" do
    test "returns open entries with job client name", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00]
      })

      snapshot = TimeTracking.snapshot_for_sms_ai(biz.id)
      assert length(snapshot) == 1
      [row] = snapshot
      assert row["job_id"] == job.id
      assert row["job_client_name"] == "Angela Bertrand"
      assert row["started_at"] == "2026-05-11T08:00:00"
    end

    test "excludes closed entries", %{biz: biz, job: job} do
      time_entry_fixture(%{
        job_id: job.id,
        business_id: biz.id,
        started_at: ~N[2026-05-11 08:00:00],
        ended_at: ~N[2026-05-11 14:00:00]
      })

      assert TimeTracking.snapshot_for_sms_ai(biz.id) == []
    end
  end
end
