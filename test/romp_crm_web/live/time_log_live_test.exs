defmodule RompCrmWeb.TimeLogLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures
  import RompCrm.TimeTrackingFixtures

  setup %{conn: conn} do
    user = user_fixture()
    biz = business_fixture(%{owner_user: user})
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user, biz: biz}
  end

  test "renders the time log page with table", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/time-log")
    # page loads without error
  end

  test "shows time entry row when entries exist", %{conn: conn, biz: biz} do
    job = job_fixture(%{business_id: biz.id, client_name: "Angela Bertrand"})

    time_entry_fixture(%{
      business_id: biz.id,
      job_id: job.id,
      started_at: ~N[2026-05-11 08:00:00],
      ended_at: ~N[2026-05-11 14:00:00]
    })

    {:ok, view, _html} = live(conn, ~p"/time-log")
    assert has_element?(view, "#time-log-table")
    refute has_element?(view, "#time-log-empty")
  end

  test "shows duration for completed entry", %{conn: conn, biz: biz} do
    job = job_fixture(%{business_id: biz.id, client_name: "Angela Bertrand"})

    entry =
      time_entry_fixture(%{
        business_id: biz.id,
        job_id: job.id,
        started_at: ~N[2026-05-11 08:00:00],
        ended_at: ~N[2026-05-11 14:00:00]
      })

    {:ok, view, _html} = live(conn, ~p"/time-log")
    assert has_element?(view, "#time-entry-dur-#{entry.id}", "6h")
  end

  test "shows in-progress badge for open entry", %{conn: conn, biz: biz} do
    job = job_fixture(%{business_id: biz.id, client_name: "Dave Wohl"})

    entry =
      time_entry_fixture(%{
        business_id: biz.id,
        job_id: job.id,
        started_at: ~N[2026-05-11 09:00:00]
      })

    {:ok, view, _html} = live(conn, ~p"/time-log")
    assert has_element?(view, "#time-entry-open-#{entry.id}", "In progress")
  end

  test "shows empty state when no entries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/time-log")
    assert has_element?(view, "#time-log-empty")
  end

  test "entries from other businesses are not shown", %{conn: conn} do
    other_biz = business_fixture()
    other_job = job_fixture(%{business_id: other_biz.id, client_name: "Other Client"})
    time_entry_fixture(%{business_id: other_biz.id, job_id: other_job.id})

    {:ok, view, _html} = live(conn, ~p"/time-log")
    # No entries from other business visible
    assert has_element?(view, "#time-log-empty")
  end
end
