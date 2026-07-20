defmodule RompCrm.LocalWallClockTest do
  use ExUnit.Case, async: true

  alias RompCrm.LocalWallClock

  test "now/1 matches DateTime.now hour and minute for the zone" do
    tz = "America/New_York"
    wall = LocalWallClock.now(tz)
    {:ok, dt} = DateTime.now(tz)

    assert wall.year == dt.year
    assert wall.month == dt.month
    assert wall.day == dt.day
    assert wall.hour == dt.hour
    assert wall.minute == dt.minute
  end

  test "now/1 falls back for invalid timezone names" do
    assert %NaiveDateTime{} = LocalWallClock.now("Not/A_Zone")
  end

  test "today/1 matches the date portion of now/1" do
    tz = "America/Chicago"
    assert LocalWallClock.today(tz) == NaiveDateTime.to_date(LocalWallClock.now(tz))
  end
end
