defmodule RompCrm.SmsInboundProcessorBookingTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.SmsConversations
  alias RompCrm.SmsInboundProcessor
  alias RompCrm.SmsPendingBookingProposals

  defp setup_business(_ctx) do
    user = user_fixture()
    {:ok, user} = RompCrm.Accounts.update_user_profile(user, %{phone: "+15555550123"})
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

  test "create with phone and work asks before texting customer", %{
    user: user,
    business: business
  } do
    payload =
      Jason.encode!(%{
        "assistant_sms" => "Added Jasmine Blair for the kitchen sink replacement.",
        "job_actions" => [
          %{
            "intent" => "create",
            "job" => %{
              "client_name" => "Jasmine Blair",
              "phone" => "8027349409",
              "work_description" => "replace kitchen sink"
            }
          }
        ],
        "proposed_booking_initiates" => [
          %{
            "client_name" => "Jasmine Blair",
            "phone" => "8027349409",
            "job_type_label" => "kitchen sink replacement",
            "duration_min_minutes" => 90,
            "duration_max_minutes" => 120
          }
        ]
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    assert reply =~ "Jasmine"
    assert reply =~ "?"
    assert Bookings.active_links_for_client_phone("18027349409") == []
    assert SmsPendingBookingProposals.get(business.id, user.phone_normalized)
  end

  test "yes after pending booking proposal texts the customer", %{user: user, business: business} do
    payload =
      Jason.encode!(%{
        "assistant_sms" => "Added Bob.",
        "job_actions" => [
          %{
            "intent" => "create",
            "job" => %{
              "client_name" => "Bob Smith",
              "phone" => "8025300293",
              "work_description" => "toilet flange"
            }
          }
        ],
        "proposed_booking_initiates" => [
          %{
            "client_name" => "Bob Smith",
            "phone" => "8025300293",
            "job_type_label" => "toilet flange",
            "duration_min_minutes" => 90,
            "duration_max_minutes" => 120
          }
        ]
      })

    assert {:ok, _} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    confirm =
      Jason.encode!(%{
        "turn_intent" => "confirm_pending_booking_outreach",
        "assistant_sms" => "Sending Bob a scheduling text.",
        "job_actions" => [],
        "booking_actions" => []
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> confirm,
               delivery: :in_app
             )

    assert reply =~ "Bob" or reply =~ "booking" or reply =~ "Sent"
    assert [_link] = Bookings.active_links_for_client_phone("18025300293")
  end

  test "explicit schedule consent can create the lead and start booking in one turn", %{
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
             SmsInboundProcessor.process(
               user,
               business.id,
               "STUB_JSON text her to schedule " <> payload,
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

  test "yes with scheduling SMS disabled and no pending continues instead of canned reply", %{
    user: user,
    business: business
  } do
    prev = Application.get_env(:romp_crm, :customer_scheduling_sms_enabled)

    on_exit(fn ->
      if is_nil(prev) do
        Application.delete_env(:romp_crm, :customer_scheduling_sms_enabled)
      else
        Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, prev)
      end
    end)

    Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, false)
    refute SmsPendingBookingProposals.get(business.id, user.phone_normalized)

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "yes", delivery: :in_app)

    refute reply =~ "scheduling texts are temporarily turned off"
  end

  test "yes with pending booking and scheduling SMS disabled explains feature is off", %{
    user: user,
    business: business
  } do
    prev = Application.get_env(:romp_crm, :customer_scheduling_sms_enabled)

    on_exit(fn ->
      if is_nil(prev) do
        Application.delete_env(:romp_crm, :customer_scheduling_sms_enabled)
      else
        Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, prev)
      end
    end)

    Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, false)

    _ =
      SmsPendingBookingProposals.store!(business.id, user.id, user.phone_normalized, %{
        "client_name" => "Pat Pending",
        "phone" => "8025550188",
        "job_type_label" => "drain clear",
        "duration_min_minutes" => 60,
        "duration_max_minutes" => 90,
        "job_id" => nil
      })

    confirm =
      Jason.encode!(%{
        "turn_intent" => "confirm_pending_booking_outreach",
        "assistant_sms" => "",
        "job_actions" => []
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> confirm,
               delivery: :in_app
             )

    assert reply =~ "scheduling texts are temporarily turned off"
    assert SmsPendingBookingProposals.get(business.id, user.phone_normalized) == nil
  end

  test "SMS phone update syncs linked client so merge-on-read keeps the number", %{
    user: user,
    business: business
  } do
    assert {:ok, client} =
             RompCrm.Clients.create_client(%{
               business_id: business.id,
               client_name: "Carolyn Brewer"
             })

    job =
      job_fixture(%{
        business_id: business.id,
        client_id: client.id,
        client_name: "Carolyn Brewer",
        phone: nil,
        status: :pending
      })

    payload =
      Jason.encode!(%{
        "assistant_sms" => "Updated Carolyn Brewer's phone number.",
        "job_actions" => [
          %{
            "intent" => "update",
            "job_id" => job.id,
            "updates" => %{"phone" => "8023497583"}
          }
        ]
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    assert reply =~ "Carolyn" or reply =~ "phone" or reply =~ "Updated"

    client = RompCrm.Clients.get_client!(client.id, business.id)
    assert client.phone in ["8023497583", "+18023497583", "18023497583"]
    assert RompCrm.Jobs.get_job!(job.id, business.id).phone == client.phone
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
