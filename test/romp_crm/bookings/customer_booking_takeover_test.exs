defmodule RompCrm.Bookings.CustomerBookingTakeoverTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.Bookings
  alias RompCrm.Bookings.CustomerBookingProcessor
  alias RompCrm.ClientChats
  alias RompCrm.SmsConversations

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  setup do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    phone = "18025559876"

    {:ok, client} =
      RompCrm.Clients.create_client(%{
        business_id: business.id,
        client_name: "Jordan Lee",
        phone: "+18025559876"
      })

    {:ok, job} =
      RompCrm.Jobs.create_job(%{
        business_id: business.id,
        client_name: "Jordan Lee",
        phone: "+18025559876",
        work_description: "faucet repair",
        status: "lead"
      })

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        client_id: client.id,
        job_id: job.id,
        job_type_label: "faucet repair",
        duration_min_minutes: 90,
        duration_max_minutes: 120,
        client_phone_normalized: phone
      })

    %{user: user, business: business, phone: phone, link: link}
  end

  test "inbound SMS during human takeover is recorded without agent reply", %{
    user: user,
    business: business,
    phone: phone
  } do
    :ok = ClientChats.take_over!(user, business.id, phone)

    params = %{
      "From" => "+18025559876",
      "Body" => "Can we do Tuesday morning?",
      "MessageSid" => "SM_takeover_test"
    }

    assert {:ok, :human_takeover_silent} = CustomerBookingProcessor.deliver_from_twilio(params)

    msgs = SmsConversations.list_client_thread_messages(business.id, phone)
    inbound = Enum.filter(msgs, &(&1.direction == "inbound"))
    assert Enum.any?(inbound, &String.contains?(&1.body, "Tuesday"))

    refute Enum.any?(msgs, fn m ->
             m.direction == "outbound" and m.channel == "sms" and String.contains?(m.body, "Tuesday")
           end)
  end
end
