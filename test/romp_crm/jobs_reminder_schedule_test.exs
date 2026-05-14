defmodule RompCrm.JobsReminderScheduleTest do
  use RompCrm.DataCase, async: false

  import RompCrm.AccountsFixtures

  alias RompCrm.Jobs
  alias RompCrm.Repo

  test "format_schedule_date_time includes time when set" do
    d = ~D[2026-06-01]
    t = ~T[14:30:00]
    assert Jobs.format_schedule_date_time(d, t) == "2026-06-01 14:30"
    assert Jobs.format_schedule_date_time(d, nil) == "2026-06-01"
  end

  test "list_work_items_for_schedule_reminders excludes WI when same date as job" do
    owner = user_fixture()
    {:ok, biz} = RompCrm.Businesses.create_business(owner, %{name: "WI Rem Biz"})
    today = Date.utc_today()
    other = Date.add(today, 3)

    {:ok, job} =
      Jobs.create_job(%{
        "business_id" => biz.id,
        "client_name" => "Same date client",
        "priority" => "normal",
        "status" => "pending",
        "scheduled_on" => Date.to_iso8601(other),
        "work_items" => [
          %{"title" => "Same day item", "scheduled_on" => Date.to_iso8601(other)}
        ]
      })

    job = Repo.preload(job, [:work_items])
    [wi] = job.work_items

    assert Jobs.list_work_items_for_schedule_reminders(biz.id, 30) == []

    {:ok, _} =
      Jobs.update_job_work_item(job, wi.id, %{
        "scheduled_on" => Date.to_iso8601(Date.add(other, 1))
      })

    pairs = Jobs.list_work_items_for_schedule_reminders(biz.id, 30)
    assert length(pairs) == 1
    {j, w} = hd(pairs)
    assert j.id == job.id
    assert w.id == wi.id
  end
end
