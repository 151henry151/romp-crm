defmodule RompCrm.Bookings.JobScheduleSyncTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.Bookings.JobScheduleSync
  alias RompCrm.Jobs

  test "sync_from_booking sets job and work item schedule and moves lead to pending" do
    user = user_fixture()
    business = business_fixture(%{owner_user: user, name: "Sync Test Co"})

    {:ok, job} =
      Jobs.create_job(%{
        business_id: business.id,
        client_name: "Jasmine Blair",
        phone: "+18027349389",
        work_description: "Fix camping sink",
        status: :lead,
        work_items: [%{title: "Fix camping sink", sort_order: 0}]
      })

    [wi] = job.work_items

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        job_id: job.id,
        client_id: job.client_id,
        job_type_label: "Fix camping sink",
        duration_min_minutes: 90,
        duration_max_minutes: 120,
        client_phone_normalized: "18027349389"
      })

    {:ok, booking} =
      Bookings.create_booking(%{
        business_id: business.id,
        technician_user_id: user.id,
        booking_link_id: link.id,
        client_id: job.client_id,
        job_id: job.id,
        starts_at: ~U[2026-06-17 19:00:00Z],
        ends_at: ~U[2026-06-17 21:00:00Z],
        status: "confirmed",
        confirmed_via: "sms"
      })

    assert {:ok, updated} = JobScheduleSync.sync_from_booking(booking)
    assert updated.status == :pending
    assert updated.scheduled_on == ~D[2026-06-17]
    assert updated.scheduled_time == ~T[15:00:00]

    updated = Jobs.get_job!(job.id, business.id)
    [updated_wi] = updated.work_items
    assert updated_wi.id == wi.id
    assert updated_wi.scheduled_on == ~D[2026-06-17]
    assert updated_wi.scheduled_time == ~T[15:00:00]
  end
end
