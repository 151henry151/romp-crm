defmodule RompCrm.Ai.SmsStatedWallTimeTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsStatedWallTime

  describe "extract_times/1" do
    test "parses 12-hour times with am/pm" do
      assert [~T[10:45:00]] = SmsStatedWallTime.extract_times("Clock me in for the day at 10:45 am")
      assert [~T[10:45:00]] = SmsStatedWallTime.extract_times("Started at Sarah's job at 10:45am")
      assert [~T[08:30:00]] = SmsStatedWallTime.extract_times("Clock me in for the day at 8:30 a.m. this morning")
      assert [~T[18:00:00]] = SmsStatedWallTime.extract_times("Clock me out for the day at 6pm")
      assert [~T[15:30:00]] = SmsStatedWallTime.extract_times("remind me at 3:30pm")
    end

    test "parses noon and midnight" do
      assert [~T[12:00:00]] = SmsStatedWallTime.extract_times("lunch at noon")
      assert [~T[00:00:00]] = SmsStatedWallTime.extract_times("until midnight")
    end

    test "returns unique times in appearance order" do
      assert [~T[08:00:00], ~T[16:00:00]] =
               SmsStatedWallTime.extract_times("Bob worked from 8am to 4pm today")
    end

    test "ignores ISO datetimes without am/pm" do
      assert [] = SmsStatedWallTime.extract_times("clocked_in_at\":\"2026-07-28T08:30:00\"")
    end

    test "returns empty when no clock time is stated" do
      assert [] = SmsStatedWallTime.extract_times("Clock me in for the day")
    end
  end

  describe "apply_to_result/2" do
    test "overrides hallucinated employee clock-in when SMS states one time" do
      result = %{
        assistant_sms: "Clocked you in for the day at 8:30 AM.",
        emp_operations: [{:emp_clock_in_by_id, 6, ~N[2026-07-28 08:30:00]}],
        time_operations: []
      }

      assert %{
               assistant_sms: "Clocked you in for the day at 10:45 AM.",
               emp_operations: [{:emp_clock_in_by_id, 6, ~N[2026-07-28 10:45:00]}],
               time_operations: []
             } =
               SmsStatedWallTime.apply_to_result(
                 result,
                 "Clock me in for the day at 10:45 am"
               )
    end

    test "overrides job clock-in when SMS states one time" do
      result = %{
        assistant_sms: "Clocked in at 8:00 AM.",
        emp_operations: [],
        time_operations: [{:clock_in_by_id, 135, ~N[2026-07-28 08:00:00]}]
      }

      assert %{
               time_operations: [{:clock_in_by_id, 135, ~N[2026-07-28 10:45:00]}]
             } =
               SmsStatedWallTime.apply_to_result(
                 result,
                 "Started at Sarah's job at 10:45am"
               )
    end

    test "does not override when model time already matches stated time" do
      result = %{
        assistant_sms: "Clocked you in for the day at 10:45 AM.",
        emp_operations: [{:emp_clock_in_by_id, 6, ~N[2026-07-28 10:45:00]}],
        time_operations: []
      }

      assert ^result =
               SmsStatedWallTime.apply_to_result(
                 result,
                 "Clock me in for the day at 10:45 am"
               )
    end

    test "does not override when multiple distinct times are stated" do
      result = %{
        assistant_sms: "Logged Bob 9am-4pm.",
        emp_operations: [
          {:emp_log_shift_by_id, 2, ~N[2026-07-28 09:00:00], ~N[2026-07-28 16:00:00], nil, nil}
        ],
        time_operations: []
      }

      assert ^result =
               SmsStatedWallTime.apply_to_result(result, "Bob worked from 8am to 4pm today")
    end

    test "does not override when SMS has no stated clock time" do
      result = %{
        assistant_sms: "Clocked you in for the day at 4:29 PM.",
        emp_operations: [{:emp_clock_in_by_id, 6, ~N[2026-07-23 16:29:07]}],
        time_operations: []
      }

      assert ^result = SmsStatedWallTime.apply_to_result(result, "Clock me in for the day")
    end

    test "overrides employee clock-out when SMS states one time" do
      result = %{
        assistant_sms: "Clocked you out for the day at 5:00 PM.",
        emp_operations: [{:emp_clock_out_by_id, 6, ~N[2026-07-28 17:00:00]}],
        time_operations: []
      }

      assert %{
               emp_operations: [{:emp_clock_out_by_id, 6, ~N[2026-07-28 18:00:00]}],
               assistant_sms: "Clocked you out for the day at 6:00 PM."
             } =
               SmsStatedWallTime.apply_to_result(result, "Clock me out for the day at 6pm")
    end
  end
end
