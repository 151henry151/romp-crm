defmodule RompCrmWeb.TwilioWebhookClientBookingTest do
  use RompCrmWeb.ConnCase

  alias RompCrm.Accounts
  alias RompCrm.AccountsFixtures
  alias RompCrm.Bookings
  alias RompCrm.Businesses
  alias RompCrm.Repo

  @client_phone "+18025300999"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, business} = Businesses.create_business(user, %{name: "Webhook Booking Co"})
    {:ok, _} = Accounts.update_user_profile(user, %{phone: "+15555550123"})

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        job_type_label: "boiler service",
        client_phone_normalized: "18025300999"
      })

    {:ok, conn: conn, business: business, link: link}
  end

  test "inbound SMS from a client phone with an active link is routed to the booking processor",
       %{conn: conn, business: business, link: link} do
    body =
      "STUB_BOOK " <>
        Jason.encode!(%{
          "reply_sms" => "Confirmed for Tuesday!",
          "resolved_booking_link_id" => link.id,
          "action" => %{
            "type" => "hard_booking",
            "starts_at" => "2026-06-16T18:00:00Z",
            "ends_at" => "2026-06-16T20:00:00Z"
          }
        })

    conn =
      post(conn, ~p"/webhooks/twilio/sms", %{
        "Body" => body,
        "From" => @client_phone,
        "MessageSid" => "SMclientbook"
      })

    assert response(conn, 200) =~ "<Response>"

    assert [booking] =
             Bookings.list_confirmed_bookings(
               business.id,
               ~U[2026-06-16 00:00:00Z],
               ~U[2026-06-17 00:00:00Z]
             )

    assert booking.confirmed_via == "sms"
    assert Repo.reload!(link).status == "booked"
  end

  test "inbound SMS from an unknown phone with no links still returns 200 TwiML", %{conn: conn} do
    conn =
      post(conn, ~p"/webhooks/twilio/sms", %{
        "Body" => "hello",
        "From" => "+19998887777",
        "MessageSid" => "SMnolink"
      })

    assert response(conn, 200) =~ "<Response>"
  end
end
