defmodule RompCrm.Scheduling.PrefsTest do
  use ExUnit.Case, async: true

  alias RompCrm.Scheduling.Prefs

  test "decode of nil and empty yields defaults" do
    for raw <- [nil, ""] do
      prefs = Prefs.decode(raw)
      assert prefs.timezone == "America/New_York"
      assert prefs.workday_start == ~T[08:00:00]
      assert prefs.workday_end == ~T[17:00:00]
      assert prefs.work_days == [1, 2, 3, 4, 5]
      assert prefs.buffer_minutes == 30
    end
  end

  test "decode of invalid JSON yields defaults" do
    assert Prefs.decode("{nope") == Prefs.default()
  end

  test "decode honors valid values" do
    json =
      Jason.encode!(%{
        "timezone" => "America/Chicago",
        "workday_start" => "07:30",
        "workday_end" => "18:00",
        "work_days" => [2, 3, 4, 5, 6],
        "buffer_minutes" => 45
      })

    prefs = Prefs.decode(json)
    assert prefs.timezone == "America/Chicago"
    assert prefs.workday_start == ~T[07:30:00]
    assert prefs.workday_end == ~T[18:00:00]
    assert prefs.work_days == [2, 3, 4, 5, 6]
    assert prefs.buffer_minutes == 45
  end

  test "decode clamps bad values to defaults" do
    json =
      Jason.encode!(%{
        "timezone" => "Mars/OlympusMons",
        "workday_start" => "26:00",
        "workday_end" => "also bad",
        "work_days" => [0, 8, "x", 3],
        "buffer_minutes" => -10
      })

    prefs = Prefs.decode(json)
    assert prefs.timezone == "America/New_York"
    assert prefs.workday_start == ~T[08:00:00]
    assert prefs.workday_end == ~T[17:00:00]
    assert prefs.work_days == [3]
    assert prefs.buffer_minutes == 0
  end

  test "encode round-trips" do
    prefs = %Prefs{
      timezone: "America/Denver",
      workday_start: ~T[09:00:00],
      workday_end: ~T[16:30:00],
      work_days: [1, 3, 5],
      buffer_minutes: 15
    }

    assert prefs |> Prefs.encode() |> Prefs.decode() == prefs
  end
end
