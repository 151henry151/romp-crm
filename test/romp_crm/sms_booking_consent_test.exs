defmodule RompCrm.SmsBookingConsentTest do
  use ExUnit.Case, async: true

  alias RompCrm.SmsBookingConsent

  test "keeps AI booking_initiate alongside create (no keyword consent gate)" do
    creates = [
      {:create,
       %{
         client_name: "Jasmine Blair",
         phone: "8027349409",
         work_description: "replace kitchen sink"
       }}
    ]

    booking = [
      {:booking_initiate,
       %{
         client_name: "Jasmine Blair",
         phone: "8027349409",
         job_type_label: "kitchen sink replacement",
         duration_min_minutes: 90,
         duration_max_minutes: 120
       }}
    ]

    {^creates, ^booking, []} =
      SmsBookingConsent.guard_operations(creates, booking, "anything", [])
  end

  test "builds pending from proposed_booking_initiates without initiate" do
    creates = [
      {:create,
       %{client_name: "Bob", phone: "8025300293", work_description: "faucet"}}
    ]

    proposed = [
      %{
        "client_name" => "Bob",
        "phone" => "8025300293",
        "job_type_label" => "faucet",
        "duration_min_minutes" => 90,
        "duration_max_minutes" => 120
      }
    ]

    {^creates, [], [pending]} =
      SmsBookingConsent.guard_operations(creates, [], "Bob faucet", proposed)

    assert pending["phone"] == "8025300293"
  end

  test "does not propose booking when create has scheduled_on" do
    creates = [
      {:create,
       %{
         client_name: "Jasmine Blair",
         phone: "8027420909",
         work_description: "replace kitchen sink",
         scheduled_on: ~D[2026-06-12]
       }}
    ]

    {^creates, [], []} =
      SmsBookingConsent.guard_operations(
        creates,
        [],
        "Jasmine blair, replace kitchen sink on thursday afternoon",
        []
      )
  end
end
