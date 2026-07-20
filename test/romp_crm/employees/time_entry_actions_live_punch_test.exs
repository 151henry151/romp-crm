defmodule RompCrm.Employees.TimeEntryActionsLivePunchTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.Employees.TimeEntryActions
  alias RompCrm.LocalWallClock

  import RompCrm.AccountsFixtures
  import RompCrm.EmployeesFixtures
  import RompCrm.JobsFixtures

  test "clock_in_live defaults to local wall clock, not UTC digits" do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    emp = employee_fixture(%{business_id: business.id, user_id: user.id, name: "Henry"})

    assert {:ok, entry} = TimeEntryActions.clock_in_live(business.id, user.id, emp)

    local = LocalWallClock.now("America/New_York")
    utc = NaiveDateTime.utc_now(:second)

    assert abs(NaiveDateTime.diff(entry.clocked_in_at, local)) <= 3

    if local.hour != utc.hour do
      assert entry.clocked_in_at.hour == local.hour
      refute entry.clocked_in_at.hour == utc.hour
    end
  end
end
