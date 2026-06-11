defmodule RompCrm.Scheduling.InternalJobsSourceTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.Jobs
  alias RompCrm.Scheduling.InternalJobsSource

  @tz "America/New_York"

  defp setup_business(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business}
  end

  setup :setup_business

  test "job with scheduled date and time produces a busy block", %{business: business} do
    {:ok, _} =
      Jobs.create_job(%{
        business_id: business.id,
        client_name: "Busy Bob",
        scheduled_on: ~D[2026-06-15],
        scheduled_time: ~T[10:00:00]
      })

    {:ok, blocks} =
      InternalJobsSource.fetch_busy_blocks(
        %{business_id: business.id},
        {~D[2026-06-15], ~D[2026-06-15]},
        @tz
      )

    # 10:00 ET = 14:00 UTC (DST); default 120-minute job
    assert [%{start: start_dt, end: end_dt}] = blocks
    assert start_dt == ~U[2026-06-15 14:00:00Z]
    assert end_dt == ~U[2026-06-15 16:00:00Z]
  end

  test "job scheduled with date only produces no busy block", %{business: business} do
    {:ok, _} =
      Jobs.create_job(%{
        business_id: business.id,
        client_name: "Dateless Dan",
        scheduled_on: ~D[2026-06-15]
      })

    {:ok, blocks} =
      InternalJobsSource.fetch_busy_blocks(
        %{business_id: business.id},
        {~D[2026-06-15], ~D[2026-06-15]},
        @tz
      )

    assert blocks == []
  end

  test "jobs outside the date range are excluded", %{business: business} do
    {:ok, _} =
      Jobs.create_job(%{
        business_id: business.id,
        client_name: "Future Fred",
        scheduled_on: ~D[2026-07-01],
        scheduled_time: ~T[09:00:00]
      })

    {:ok, blocks} =
      InternalJobsSource.fetch_busy_blocks(
        %{business_id: business.id},
        {~D[2026-06-15], ~D[2026-06-16]},
        @tz
      )

    assert blocks == []
  end

  test "confirmed bookings produce busy blocks; cancelled do not", %{
    business: business,
    user: user
  } do
    base = %{
      business_id: business.id,
      technician_user_id: user.id,
      starts_at: ~U[2026-06-15 17:00:00Z],
      ends_at: ~U[2026-06-15 19:00:00Z]
    }

    assert {:ok, _} = Bookings.create_booking(base)

    assert {:ok, cancelled} =
             Bookings.create_booking(%{
               base
               | starts_at: ~U[2026-06-16 17:00:00Z],
                 ends_at: ~U[2026-06-16 19:00:00Z]
             })

    assert {:ok, _} = Bookings.cancel_booking(cancelled)

    {:ok, blocks} =
      InternalJobsSource.fetch_busy_blocks(
        %{business_id: business.id},
        {~D[2026-06-15], ~D[2026-06-16]},
        @tz
      )

    assert blocks == [%{start: ~U[2026-06-15 17:00:00Z], end: ~U[2026-06-15 19:00:00Z]}]
  end
end
