defmodule RompCrmWeb.TwilioWebhookTimeTest do
  use RompCrmWeb.ConnCase

  import ExUnit.CaptureLog

  alias RompCrm.Accounts
  alias RompCrm.AccountsFixtures
  alias RompCrm.Businesses
  alias RompCrm.Employees
  alias RompCrm.Jobs
  alias RompCrm.TimeTracking

  import RompCrm.JobsFixtures
  import RompCrm.EmployeesFixtures

  setup %{conn: conn} do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    user = AccountsFixtures.user_fixture()
    {:ok, biz} = Businesses.create_business(user, %{name: "Time Test Co"})
    {:ok, _} = Accounts.update_user_profile(user, %{phone: "+15555550200"})

    {:ok, conn: conn, sms_business: biz}
  end

  # ── Job time tracking ──────────────────────────────────────────────────────

  test "STUB_TIME_IN clocks in to a job", %{conn: conn, sms_business: biz} do
    job = job_fixture(%{business_id: biz.id, client_name: "Angela Bertrand"})

    body =
      "STUB_TIME_IN " <>
        Jason.encode!(%{"job_id" => job.id, "started_at" => "2026-05-11T08:00:00"})

    conn =
      post(conn, ~p"/webhooks/twilio/sms", %{
        "Body" => body,
        "From" => "+15555550200",
        "MessageSid" => "SMtimein01"
      })

    assert response(conn, 200) =~ "<Response>"

    entries = TimeTracking.list_time_entries_for_job(job.id, biz.id)
    assert length(entries) == 1
    assert hd(entries).started_at == ~N[2026-05-11 08:00:00]
    assert hd(entries).ended_at == nil
  end

  test "STUB_TIME_OUT clocks out from a job by closing open entry", %{
    conn: conn,
    sms_business: biz
  } do
    job = job_fixture(%{business_id: biz.id, client_name: "Angela Bertrand"})

    {:ok, _open_entry} =
      TimeTracking.create_time_entry(%{
        business_id: biz.id,
        job_id: job.id,
        started_at: ~N[2026-05-11 08:00:00]
      })

    body =
      "STUB_TIME_OUT " <>
        Jason.encode!(%{"job_id" => job.id, "ended_at" => "2026-05-11T14:00:00"})

    post(conn, ~p"/webhooks/twilio/sms", %{
      "Body" => body,
      "From" => "+15555550200",
      "MessageSid" => "SMtimeout01"
    })

    entries = TimeTracking.list_time_entries_for_job(job.id, biz.id)
    assert length(entries) == 1
    assert hd(entries).ended_at == ~N[2026-05-11 14:00:00]
  end

  test "STUB_TIME_IN with invalid job_id is skipped, no entry created", %{
    conn: conn,
    sms_business: biz
  } do
    body =
      "STUB_TIME_IN " <>
        Jason.encode!(%{"job_id" => 999_999, "started_at" => "2026-05-11T08:00:00"})

    log =
      capture_log([level: :info], fn ->
        post(conn, ~p"/webhooks/twilio/sms", %{
          "Body" => body,
          "From" => "+15555550200",
          "MessageSid" => "SMtimebadid"
        })
      end)

    assert log =~ "time_clock_in skipped"
    assert TimeTracking.list_time_entries(biz.id) == []
  end

  test "STUB_TIME_OUT when no open entry is skipped gracefully", %{
    conn: conn,
    sms_business: biz
  } do
    job = job_fixture(%{business_id: biz.id})

    body =
      "STUB_TIME_OUT " <>
        Jason.encode!(%{"job_id" => job.id, "ended_at" => "2026-05-11T14:00:00"})

    log =
      capture_log([level: :info], fn ->
        post(conn, ~p"/webhooks/twilio/sms", %{
          "Body" => body,
          "From" => "+15555550200",
          "MessageSid" => "SMnoopenentry"
        })
      end)

    assert log =~ "time_clock_out skipped"
    assert TimeTracking.list_time_entries_for_job(job.id, biz.id) == []
  end

  # ── Employee time tracking ─────────────────────────────────────────────────

  test "STUB_EMP_IN clocks in an employee", %{conn: conn, sms_business: biz} do
    emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

    body =
      "STUB_EMP_IN " <>
        Jason.encode!(%{"employee_id" => emp.id, "clocked_in_at" => "2026-05-11T08:00:00"})

    post(conn, ~p"/webhooks/twilio/sms", %{
      "Body" => body,
      "From" => "+15555550200",
      "MessageSid" => "SMempin01"
    })

    entries = Employees.list_time_entries(emp.id, biz.id)
    assert length(entries) == 1
    assert hd(entries).clocked_in_at == ~N[2026-05-11 08:00:00]
    assert hd(entries).clocked_out_at == nil
  end

  test "STUB_EMP_OUT clocks out an employee by closing open entry", %{
    conn: conn,
    sms_business: biz
  } do
    emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

    {:ok, _open} =
      Employees.create_time_entry(%{
        business_id: biz.id,
        employee_id: emp.id,
        clocked_in_at: ~N[2026-05-11 08:00:00]
      })

    body =
      "STUB_EMP_OUT " <>
        Jason.encode!(%{"employee_id" => emp.id, "clocked_out_at" => "2026-05-11T16:00:00"})

    post(conn, ~p"/webhooks/twilio/sms", %{
      "Body" => body,
      "From" => "+15555550200",
      "MessageSid" => "SMempout01"
    })

    [entry] = Employees.list_time_entries(emp.id, biz.id)
    assert entry.clocked_out_at == ~N[2026-05-11 16:00:00]
  end

  test "STUB_EMP_LUNCH records lunch for an employee with open entry", %{
    conn: conn,
    sms_business: biz
  } do
    emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

    {:ok, _open} =
      Employees.create_time_entry(%{
        business_id: biz.id,
        employee_id: emp.id,
        clocked_in_at: ~N[2026-05-11 08:00:00]
      })

    body =
      "STUB_EMP_LUNCH " <>
        Jason.encode!(%{
          "employee_id" => emp.id,
          "lunch_start_at" => "2026-05-11T12:00:00",
          "lunch_end_at" => "2026-05-11T13:00:00"
        })

    post(conn, ~p"/webhooks/twilio/sms", %{
      "Body" => body,
      "From" => "+15555550200",
      "MessageSid" => "SMemplunch01"
    })

    [entry] = Employees.list_time_entries(emp.id, biz.id)
    assert entry.lunch_start_at == ~N[2026-05-11 12:00:00]
    assert entry.lunch_end_at == ~N[2026-05-11 13:00:00]
  end

  test "STUB_EMP_IN with invalid employee_id is skipped", %{conn: conn, sms_business: biz} do
    body =
      "STUB_EMP_IN " <>
        Jason.encode!(%{"employee_id" => 999_999, "clocked_in_at" => "2026-05-11T08:00:00"})

    log =
      capture_log([level: :info], fn ->
        post(conn, ~p"/webhooks/twilio/sms", %{
          "Body" => body,
          "From" => "+15555550200",
          "MessageSid" => "SMemp_badid"
        })
      end)

    assert log =~ "emp_clock_in skipped"
    assert Employees.list_all_time_entries(biz.id) == []
  end

  # ── Existing job ops still work alongside time ops ──────────────────────

  test "STUB_UPDATE still works when new extractors return empty", %{
    conn: conn,
    sms_business: biz
  } do
    job = job_fixture(%{business_id: biz.id, client_name: "Angela Bertrand", address: nil})

    body =
      "STUB_UPDATE " <>
        Jason.encode!(%{
          "job_id" => job.id,
          "updates" => %{"address" => "99 Oak St"}
        })

    log =
      capture_log([level: :info], fn ->
        post(conn, ~p"/webhooks/twilio/sms", %{
          "Body" => body,
          "From" => "+15555550200",
          "MessageSid" => "SMstillupdates"
        })
      end)

    assert log =~ "Twilio SMS update applied"
    assert Jobs.get_job!(job.id, biz.id).address == "99 Oak St"
  end
end
