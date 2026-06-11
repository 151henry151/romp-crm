defmodule RompCrm.Scheduling.AvailabilityEngineTest do
  use ExUnit.Case, async: true

  alias RompCrm.Scheduling.AvailabilityEngine
  alias RompCrm.Scheduling.Prefs

  # Monday 2026-06-15 — DST in effect for America/New_York (UTC-4).
  @monday ~D[2026-06-15]
  @tuesday ~D[2026-06-16]

  defp utc(iso), do: elem(DateTime.from_iso8601(iso), 1)

  defp block(start_iso, end_iso), do: %{start: utc(start_iso), end: utc(end_iso)}

  defp prefs(overrides \\ %{}) do
    Map.merge(
      %Prefs{
        timezone: "America/New_York",
        workday_start: ~T[08:00:00],
        workday_end: ~T[17:00:00],
        work_days: [1, 2, 3, 4, 5],
        buffer_minutes: 0
      },
      overrides
    )
  end

  describe "merge_busy_blocks/1" do
    test "returns empty for no blocks" do
      assert AvailabilityEngine.merge_busy_blocks([]) == []
    end

    test "keeps disjoint blocks sorted" do
      b1 = block("2026-06-15T14:00:00Z", "2026-06-15T15:00:00Z")
      b2 = block("2026-06-15T10:00:00Z", "2026-06-15T11:00:00Z")

      assert AvailabilityEngine.merge_busy_blocks([b1, b2]) == [b2, b1]
    end

    test "merges overlapping blocks" do
      b1 = block("2026-06-15T10:00:00Z", "2026-06-15T12:00:00Z")
      b2 = block("2026-06-15T11:00:00Z", "2026-06-15T13:00:00Z")

      assert AvailabilityEngine.merge_busy_blocks([b1, b2]) ==
               [block("2026-06-15T10:00:00Z", "2026-06-15T13:00:00Z")]
    end

    test "merges adjacent blocks" do
      b1 = block("2026-06-15T10:00:00Z", "2026-06-15T11:00:00Z")
      b2 = block("2026-06-15T11:00:00Z", "2026-06-15T12:00:00Z")

      assert AvailabilityEngine.merge_busy_blocks([b1, b2]) ==
               [block("2026-06-15T10:00:00Z", "2026-06-15T12:00:00Z")]
    end

    test "absorbs nested blocks" do
      outer = block("2026-06-15T09:00:00Z", "2026-06-15T15:00:00Z")
      inner = block("2026-06-15T10:00:00Z", "2026-06-15T11:00:00Z")

      assert AvailabilityEngine.merge_busy_blocks([inner, outer]) == [outer]
    end
  end

  describe "available_slots/5" do
    test "free workday yields slots from workday start to last fitting start" do
      slots = AvailabilityEngine.available_slots([], @monday, @monday, prefs(), 120)

      # 08:00–17:00 ET = 12:00–21:00 UTC during DST; 120-min job, 30-min steps:
      # starts 12:00..19:00 UTC inclusive → 15 slots
      assert length(slots) == 15
      assert hd(slots) == block("2026-06-15T12:00:00Z", "2026-06-15T14:00:00Z")
      assert List.last(slots) == block("2026-06-15T19:00:00Z", "2026-06-15T21:00:00Z")
    end

    test "busy block carves out conflicting slots" do
      # Busy 10:00–12:00 ET = 14:00–16:00 UTC
      busy = [block("2026-06-15T14:00:00Z", "2026-06-15T16:00:00Z")]
      slots = AvailabilityEngine.available_slots(busy, @monday, @monday, prefs(), 120)

      # No slot may overlap 14:00–16:00 UTC
      refute Enum.any?(slots, fn s ->
               DateTime.compare(s.start, utc("2026-06-15T16:00:00Z")) == :lt and
                 DateTime.compare(s.end, utc("2026-06-15T14:00:00Z")) == :gt
             end)

      # 12:00 UTC start (ends 14:00) still fits; 16:00 UTC start fits
      assert Enum.any?(slots, &(&1.start == utc("2026-06-15T12:00:00Z")))
      assert Enum.any?(slots, &(&1.start == utc("2026-06-15T16:00:00Z")))
    end

    test "buffer expands busy blocks" do
      busy = [block("2026-06-15T14:00:00Z", "2026-06-15T16:00:00Z")]

      slots =
        AvailabilityEngine.available_slots(
          busy,
          @monday,
          @monday,
          prefs(%{buffer_minutes: 30}),
          120
        )

      # With 30-min buffer busy is effectively 13:30–16:30 UTC.
      # A 120-min slot starting 11:30 UTC would end 13:30 — allowed; 12:00 would end 14:00 — not.
      refute Enum.any?(slots, &(&1.start == utc("2026-06-15T12:00:00Z")))
      assert Enum.any?(slots, &(&1.start == utc("2026-06-15T16:30:00Z")))
    end

    test "non-work days yield no slots" do
      saturday = ~D[2026-06-20]
      assert AvailabilityEngine.available_slots([], saturday, saturday, prefs(), 60) == []
    end

    test "multi-day range covers each work day" do
      slots = AvailabilityEngine.available_slots([], @monday, @tuesday, prefs(), 480)

      days =
        slots
        |> Enum.map(fn s -> s.start |> DateTime.shift_zone!("America/New_York") |> DateTime.to_date() end)
        |> Enum.uniq()

      assert days == [@monday, @tuesday]
    end

    test "duration longer than workday yields no slots" do
      assert AvailabilityEngine.available_slots([], @monday, @monday, prefs(), 600) == []
    end
  end

  describe "check_conflict/3" do
    test "available when window has no busy overlap" do
      busy = [block("2026-06-15T08:00:00Z", "2026-06-15T09:00:00Z")]
      window = block("2026-06-15T10:00:00Z", "2026-06-15T12:00:00Z")

      assert AvailabilityEngine.check_conflict(busy, window, 60) == :available
    end

    test "partial when busy overlaps but a duration-length free run remains" do
      busy = [block("2026-06-15T10:00:00Z", "2026-06-15T11:00:00Z")]
      window = block("2026-06-15T10:00:00Z", "2026-06-15T13:00:00Z")

      assert AvailabilityEngine.check_conflict(busy, window, 60) == :partial
    end

    test "conflict when no duration-length free run exists in window" do
      busy = [
        block("2026-06-15T10:00:00Z", "2026-06-15T11:00:00Z"),
        block("2026-06-15T11:30:00Z", "2026-06-15T13:00:00Z")
      ]

      window = block("2026-06-15T10:00:00Z", "2026-06-15T13:00:00Z")

      assert AvailabilityEngine.check_conflict(busy, window, 60) == :conflict
    end

    test "conflict when window is fully covered" do
      busy = [block("2026-06-15T09:00:00Z", "2026-06-15T14:00:00Z")]
      window = block("2026-06-15T10:00:00Z", "2026-06-15T12:00:00Z")

      assert AvailabilityEngine.check_conflict(busy, window, 60) == :conflict
    end
  end

  describe "working_hours_busy_blocks/3" do
    test "complement covers nights and the weekend" do
      # Friday→Monday in ET; Sat/Sun fully busy, Fri/Mon nights busy
      blocks =
        AvailabilityEngine.working_hours_busy_blocks(~D[2026-06-19], ~D[2026-06-22], prefs())

      sat_noon_utc = utc("2026-06-20T16:00:00Z")

      assert Enum.any?(blocks, fn b ->
               DateTime.compare(b.start, sat_noon_utc) != :gt and
                 DateTime.compare(b.end, sat_noon_utc) == :gt
             end)
    end
  end
end
