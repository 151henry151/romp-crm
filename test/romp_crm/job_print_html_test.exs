defmodule RompCrm.JobPrint.HtmlTest do
  use ExUnit.Case, async: true

  alias RompCrm.JobPrint.Html
  alias RompCrm.Jobs.Job

  test "omits blank contact fields and empty sections" do
    job = %Job{
      id: 42,
      client_name: "Carolyn Brewer",
      phone: nil,
      client_email: "",
      work_description: "Fix sink",
      customer_comments: nil,
      notes: "   ",
      next_action: nil,
      referred_by: nil,
      status: :pending,
      priority: :normal,
      scheduled_on: nil,
      inserted_at: ~U[2026-07-20 12:00:00Z],
      updated_at: ~U[2026-07-20 12:00:00Z]
    }

    report = %{
      job: job,
      business_name: "Print Job Co",
      service_address: "—",
      billing_address: nil,
      work_items: [],
      materials: [],
      time_entries: [],
      total_minutes: 0,
      photos: []
    }

    html = Html.job_document(report, DateTime.utc_now())

    assert html =~ "Carolyn Brewer"
    assert html =~ "Fix sink"
    assert html =~ "Pending"
    refute html =~ "Phone"
    refute html =~ "Email"
    refute html =~ "Service address"
    refute html =~ "Billing address"
    refute html =~ "Scheduled"
    refute html =~ "Referred by"
    refute html =~ "Customer comments"
    refute html =~ ">Notes<"
    refute html =~ "Next action"
    refute html =~ "Work items"
    refute html =~ "Materials"
    refute html =~ "Hours logged"
    refute html =~ "Photos"
    refute html =~ "No work items"
    refute html =~ "No materials"
    refute html =~ "No hours"
    refute html =~ "No photos"
    refute html =~ "—"
  end

  test "includes populated optional sections" do
    job = %Job{
      id: 7,
      client_name: "Will Nash",
      phone: "+18025550100",
      notes: "Gate code 1234",
      status: :in_progress,
      priority: :high,
      inserted_at: ~U[2026-07-20 12:00:00Z],
      updated_at: ~U[2026-07-20 12:00:00Z]
    }

    report = %{
      job: job,
      business_name: "Print Job Co",
      service_address: "10 Main St, Middlebury, VT 05753",
      billing_address: nil,
      work_items: [],
      materials: [],
      time_entries: [],
      total_minutes: 90,
      photos: []
    }

    html = Html.job_document(report, DateTime.utc_now())

    assert html =~ "Phone"
    assert html =~ "+18025550100"
    assert html =~ "Service address"
    assert html =~ "10 Main St"
    assert html =~ "Notes"
    assert html =~ "Gate code 1234"
    assert html =~ "Hours logged"
    assert html =~ "1h 30m"
    refute html =~ "Billing address"
  end
end
