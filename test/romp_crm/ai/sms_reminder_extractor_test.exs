defmodule RompCrm.Ai.SmsReminderExtractorTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsReminderExtractor

  test "parse_actions_list/1 schedules reminder with optional job_id" do
    actions = [
      %{
        "intent" => "schedule",
        "fire_at" => "2030-01-15T16:00:00Z",
        "body" => "Call Suzy",
        "job_id" => 12,
        "metadata" => %{"no_customer_match" => true}
      }
    ]

    assert {:ok, [{:reminder_schedule, dt, "Call Suzy", 12, meta}]} =
             SmsReminderExtractor.parse_actions_list(actions)

    assert DateTime.compare(dt, ~U[2030-01-15 16:00:00Z]) == :eq
    assert meta["no_customer_match"] == true
  end

  test "naive fire_at is interpreted in reminder_wall_tz, not as UTC" do
    actions = [
      %{
        "intent" => "schedule",
        "fire_at" => "2030-06-01T15:30:00",
        "body" => "Call Jason",
        "job_id" => nil,
        "metadata" => %{}
      }
    ]

    assert {:ok, [{:reminder_schedule, dt, "Call Jason", nil, _}]} =
             SmsReminderExtractor.parse_actions_list(actions, reminder_wall_tz: "America/New_York")

    # 15:30 Eastern on 2030-06-01 is DST (EDT, UTC-4) → 19:30 UTC
    assert DateTime.compare(dt, ~U[2030-06-01 19:30:00Z]) == :eq
  end

  test "explicit Z is unchanged by reminder_wall_tz" do
    actions = [
      %{
        "intent" => "schedule",
        "fire_at" => "2030-06-01T15:30:00Z",
        "body" => "Call",
        "job_id" => nil,
        "metadata" => %{}
      }
    ]

    assert {:ok, [{:reminder_schedule, dt, "Call", nil, _}]} =
             SmsReminderExtractor.parse_actions_list(actions, reminder_wall_tz: "America/Los_Angeles")

    assert DateTime.compare(dt, ~U[2030-06-01 15:30:00Z]) == :eq
  end
end
