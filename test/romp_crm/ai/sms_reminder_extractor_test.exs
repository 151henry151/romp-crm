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
end
