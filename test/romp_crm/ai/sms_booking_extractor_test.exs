defmodule RompCrm.Ai.SmsBookingExtractorTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsBookingExtractor

  test "nil and empty lists parse to no ops" do
    assert SmsBookingExtractor.parse_actions_list(nil) == {:ok, []}
    assert SmsBookingExtractor.parse_actions_list([]) == {:ok, []}
  end

  test "parses initiate with full fields" do
    raw = [
      %{
        "intent" => "initiate",
        "client_id" => 7,
        "client_name" => "Bob Smith",
        "phone" => "802-530-0293",
        "job_id" => 12,
        "job_type_label" => "Toilet flange replacement",
        "duration_min_minutes" => 120,
        "duration_max_minutes" => 180
      }
    ]

    assert {:ok, [{:booking_initiate, attrs}]} = SmsBookingExtractor.parse_actions_list(raw)
    assert attrs.client_id == 7
    assert attrs.client_name == "Bob Smith"
    assert attrs.phone == "802-530-0293"
    assert attrs.job_id == 12
    assert attrs.job_type_label == "Toilet flange replacement"
    assert attrs.duration_min_minutes == 120
    assert attrs.duration_max_minutes == 180
  end

  test "initiate defaults durations and tolerates missing optional ids" do
    raw = [
      %{
        "intent" => "initiate",
        "client_name" => "Maria",
        "phone" => "(802) 555-0101",
        "job_type_label" => "Kitchen faucet replacement"
      }
    ]

    assert {:ok, [{:booking_initiate, attrs}]} = SmsBookingExtractor.parse_actions_list(raw)
    assert attrs.client_id == nil
    assert attrs.job_id == nil
    assert attrs.duration_min_minutes == 60
    assert attrs.duration_max_minutes == 120
  end

  test "initiate without phone errors" do
    raw = [%{"intent" => "initiate", "client_name" => "No Phone", "job_type_label" => "x"}]

    assert {:error, {:invalid_booking_action, 1, :missing_phone}} =
             SmsBookingExtractor.parse_actions_list(raw)
  end

  test "parses update_duration" do
    raw = [
      %{
        "intent" => "update_duration",
        "booking_link_id" => 3,
        "duration_min_minutes" => 90,
        "duration_max_minutes" => 150
      }
    ]

    assert {:ok, [{:booking_update_duration, 3, 90, 150}]} =
             SmsBookingExtractor.parse_actions_list(raw)
  end

  test "parses confirm_soft with UTC instants" do
    raw = [
      %{
        "intent" => "confirm_soft",
        "booking_request_id" => 5,
        "starts_at" => "2026-06-18T14:00:00Z",
        "ends_at" => "2026-06-18T17:00:00Z"
      }
    ]

    assert {:ok, [{:booking_confirm_soft, 5, starts, ends}]} =
             SmsBookingExtractor.parse_actions_list(raw)

    assert starts == ~U[2026-06-18 14:00:00Z]
    assert ends == ~U[2026-06-18 17:00:00Z]
  end

  test "confirm_soft naive times are interpreted in the wall timezone" do
    raw = [
      %{
        "intent" => "confirm_soft",
        "booking_request_id" => 5,
        "starts_at" => "2026-06-18T10:00:00",
        "ends_at" => "2026-06-18T13:00:00"
      }
    ]

    assert {:ok, [{:booking_confirm_soft, 5, starts, ends}]} =
             SmsBookingExtractor.parse_actions_list(raw, wall_tz: "America/New_York")

    # 10:00 ET = 14:00 UTC in June (DST)
    assert starts == ~U[2026-06-18 14:00:00Z]
    assert ends == ~U[2026-06-18 17:00:00Z]
  end

  test "parses cancel with optional reason" do
    raw = [%{"intent" => "cancel", "booking_id" => 9, "reason" => "customer asked"}]

    assert {:ok, [{:booking_cancel, 9, "customer asked"}]} =
             SmsBookingExtractor.parse_actions_list(raw)

    raw2 = [%{"intent" => "cancel", "booking_id" => 9}]
    assert {:ok, [{:booking_cancel, 9, nil}]} = SmsBookingExtractor.parse_actions_list(raw2)
  end

  test "unknown intent errors with index" do
    raw = [%{"intent" => "teleport"}]

    assert {:error, {:invalid_booking_action, 1, :unknown_booking_intent}} =
             SmsBookingExtractor.parse_actions_list(raw)
  end
end
