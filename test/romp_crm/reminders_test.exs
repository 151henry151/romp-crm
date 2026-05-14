defmodule RompCrm.RemindersTest do
  use ExUnit.Case, async: false

  alias RompCrm.Reminders

  describe "decode_prefs_json/1" do
    test "defaults to Eastern 09:00" do
      assert Reminders.decode_prefs_json(nil) == %{
               "job_offsets" => [1, 0],
               "timezone" => "America/New_York",
               "send_hour_local" => 9
             }
    end

    test "legacy send_hour_utc is Etc/UTC with that hour" do
      json = ~s({"job_offsets":[2,1],"send_hour_utc":14})
      got = Reminders.decode_prefs_json(json)
      assert got["timezone"] == "Etc/UTC"
      assert got["send_hour_local"] == 14
      assert got["job_offsets"] == [2, 1]
    end

    test "new keys round-trip" do
      json = ~s({"timezone":"America/Denver","send_hour_local":11,"job_offsets":[0]})
      got = Reminders.decode_prefs_json(json)
      assert got["timezone"] == "America/Denver"
      assert got["send_hour_local"] == 11
      assert got["job_offsets"] == [0]
    end

    test "replaces unknown time zone with Eastern" do
      json = ~s({"timezone":"Not/A_Zone","send_hour_local":10,"job_offsets":[0]})
      got = Reminders.decode_prefs_json(json)
      assert got["timezone"] == "America/New_York"
      assert got["send_hour_local"] == 10
    end
  end

  describe "local_send_hour_matches_now?/2" do
    test "matches Eastern local hour 9 at 14:00 UTC in January" do
      utc = ~U[2024-01-15 14:00:00Z]
      prefs = %{"timezone" => "America/New_York", "send_hour_local" => 9}

      assert Reminders.local_send_hour_matches_now?(utc, prefs)
    end

    test "does not match when hour differs" do
      utc = ~U[2024-01-15 14:00:00Z]
      prefs = %{"timezone" => "America/New_York", "send_hour_local" => 10}

      refute Reminders.local_send_hour_matches_now?(utc, prefs)
    end
  end
end
