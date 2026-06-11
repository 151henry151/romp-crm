defmodule RompCrm.SmsBookingConsentTest do
  use ExUnit.Case, async: true

  alias RompCrm.SmsBookingConsent

  test "strips initiate on same turn as create without contractor consent" do
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

    {^creates, [], [pending]} =
      SmsBookingConsent.guard_operations(creates, booking, "Jasmine Blair 8027349409 sink", [])

    assert pending["phone"] == "8027349409"
  end

  test "keeps initiate when contractor explicitly asks to text" do
    creates = [
      {:create,
       %{client_name: "Bob", phone: "8025300293", work_description: "faucet"}}
    ]

    booking = [
      {:booking_initiate,
       %{
         client_name: "Bob",
         phone: "8025300293",
         job_type_label: "faucet",
         duration_min_minutes: 90,
         duration_max_minutes: 120
       }}
    ]

    {^creates, ^booking, []} =
      SmsBookingConsent.guard_operations(
        creates,
        booking,
        "text Bob to schedule the faucet job",
        []
      )
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
