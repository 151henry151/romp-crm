defmodule RompCrm.SmsInboundProcessorBookingTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.SmsConversations
  alias RompCrm.SmsInboundProcessor

  defp setup_business(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user, name: "Booking Test Plumbing"})
    %{user: user, business: business}
  end

  setup :setup_business

  test "agent message with booking initiate creates link and first client SMS", %{
    user: user,
    business: business
  } do
    payload =
      Jason.encode!(%{
        "assistant_sms" => "Texted Bob a booking link for the flange job (2-3 hours).",
        "booking_actions" => [
          %{
            "intent" => "initiate",
            "client_name" => "Bob Smith",
            "phone" => "802-530-0293",
            "job_type_label" => "toilet flange replacement",
            "duration_min_minutes" => 120,
            "duration_max_minutes" => 180
          }
        ]
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    assert reply =~ "Texted Bob"

    [link] = Bookings.active_links_for_client_phone("18025300293")
    assert link.business_id == business.id
    assert link.technician_user_id == user.id
    assert link.duration_min_minutes == 120

    turns = SmsConversations.list_client_turns_for_ai(business.id, "18025300293")
    assert [{:assistant, first_sms}] = turns
    assert first_sms =~ "Booking Test Plumbing"
    assert first_sms =~ link.token
  end

  test "one message can create the lead and start the booking conversation", %{
    user: user,
    business: business
  } do
    payload =
      Jason.encode!(%{
        "assistant_sms" => "Added Jasmine Blair and texted her to schedule the sink replacement.",
        "job_actions" => [
          %{
            "intent" => "create",
            "job" => %{
              "client_name" => "Jasmine Blair",
              "phone" => "8027349384",
              "work_description" => "replace kitchen sink"
            }
          }
        ],
        "booking_actions" => [
          %{
            "intent" => "initiate",
            "client_name" => "Jasmine Blair",
            "phone" => "8027349384",
            "job_type_label" => "kitchen sink replacement",
            "duration_min_minutes" => 120,
            "duration_max_minutes" => 180
          }
        ]
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    assert reply =~ "Jasmine"

    # One job, one client, and a booking link tied to both — no duplicates.
    [job] = Repo.all(RompCrm.Jobs.Job)
    assert job.client_name == "Jasmine Blair"
    assert job.work_description == "replace kitchen sink"
    assert is_integer(job.client_id)
    assert Repo.aggregate(RompCrm.Clients.Client, :count) == 1

    [link] = Bookings.active_links_for_client_phone("18027349384")
    assert link.job_id == job.id
    assert link.client_id == job.client_id

    # First customer SMS: business name, openings, and the booking link.
    turns = SmsConversations.list_client_turns_for_ai(business.id, "18027349384")
    assert [{:assistant, first_sms}] = turns
    assert first_sms =~ "Booking Test Plumbing"
    assert first_sms =~ "kitchen sink replacement"
    assert first_sms =~ link.token
    assert first_sms =~ "openings"
  end

  test "booking confirm_soft via agent converts the pending request", %{
    user: user,
    business: business
  } do
    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        job_type_label: "water heater install",
        client_phone_normalized: "18025550123"
      })

    {:ok, request} =
      Bookings.create_booking_request(%{
        business_id: business.id,
        technician_user_id: user.id,
        booking_link_id: link.id,
        availability_text: "anytime Thursday",
        job_type_label: link.job_type_label
      })

    payload =
      Jason.encode!(%{
        "assistant_sms" => "Booked Bob for Thursday 10am-1pm.",
        "booking_actions" => [
          %{
            "intent" => "confirm_soft",
            "booking_request_id" => request.id,
            "starts_at" => "2026-06-18T14:00:00Z",
            "ends_at" => "2026-06-18T17:00:00Z"
          }
        ]
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    assert reply =~ "Booked Bob"
    assert Repo.reload!(request).status == "converted"
    assert Repo.reload!(link).status == "booked"
  end
end
