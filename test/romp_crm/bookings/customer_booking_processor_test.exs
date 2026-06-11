defmodule RompCrm.Bookings.CustomerBookingProcessorTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.Bookings.CustomerBookingProcessor
  alias RompCrm.SmsConversations

  @client_phone "18025300293"

  defp setup_booking(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user, name: "Green Mountain Plumbing"})

    {:ok, client} =
      RompCrm.Clients.create_client(%{
        business_id: business.id,
        client_name: "Bob Smith",
        phone: "+" <> @client_phone
      })

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        client_id: client.id,
        job_type_label: "toilet flange replacement",
        duration_min_minutes: 120,
        duration_max_minutes: 180,
        client_phone_normalized: @client_phone
      })

    %{user: user, business: business, client: client, link: link}
  end

  setup :setup_booking

  defp twilio_params(body), do: %{"Body" => body, "From" => "+" <> @client_phone, "MessageSid" => "SMclient"}

  describe "hard booking via SMS" do
    test "available time creates a confirmed booking and marks link booked", %{
      business: business,
      link: link
    } do
      body =
        "STUB_BOOK " <>
          Jason.encode!(%{
            "reply_sms" => "You're all set for Tuesday at 2pm!",
            "resolved_booking_link_id" => link.id,
            "action" => %{
              "type" => "hard_booking",
              "starts_at" => "2026-06-16T18:00:00Z",
              "ends_at" => "2026-06-16T21:00:00Z"
            }
          })

      assert {:ok, reply} = CustomerBookingProcessor.deliver_from_twilio(twilio_params(body))
      assert reply =~ "all set"

      assert [booking] =
               Bookings.list_confirmed_bookings(
                 business.id,
                 ~U[2026-06-16 00:00:00Z],
                 ~U[2026-06-17 00:00:00Z]
               )

      assert booking.booking_link_id == link.id
      assert booking.confirmed_via == "sms"
      assert Repo.reload!(link).status == "booked"

      turns = SmsConversations.list_client_turns_for_ai(business.id, @client_phone)
      assert Enum.any?(turns, fn {role, t} -> role == :client and t =~ "STUB_BOOK" end)
      assert Enum.any?(turns, fn {role, t} -> role == :assistant and t =~ "all set" end)
    end

    test "conflicting time is rejected with a fallback reply and no booking", %{
      business: business,
      user: user,
      link: link
    } do
      # Occupy the proposed window with an existing confirmed booking.
      {:ok, _} =
        Bookings.create_booking(%{
          business_id: business.id,
          technician_user_id: user.id,
          starts_at: ~U[2026-06-16 18:00:00Z],
          ends_at: ~U[2026-06-16 21:00:00Z]
        })

      body =
        "STUB_BOOK " <>
          Jason.encode!(%{
            "reply_sms" => "You're all set for Tuesday at 2pm!",
            "resolved_booking_link_id" => link.id,
            "action" => %{
              "type" => "hard_booking",
              "starts_at" => "2026-06-16T18:00:00Z",
              "ends_at" => "2026-06-16T21:00:00Z"
            }
          })

      assert {:ok, reply} = CustomerBookingProcessor.deliver_from_twilio(twilio_params(body))
      refute reply =~ "all set"
      assert reply =~ "no longer available"

      assert Repo.reload!(link).status == "pending"
    end
  end

  describe "soft availability via SMS" do
    test "stores a booking request and acknowledges", %{business: business, link: link} do
      body =
        "STUB_SOFT " <>
          Jason.encode!(%{
            "reply_sms" => "Got it — we'll be in touch to lock in a time Thursday.",
            "resolved_booking_link_id" => link.id,
            "action" => %{
              "type" => "soft_availability",
              "availability_text" => "anytime Thursday",
              "windows" => [
                %{"start" => "2026-06-18T12:00:00Z", "end" => "2026-06-18T21:00:00Z"}
              ]
            }
          })

      assert {:ok, reply} = CustomerBookingProcessor.deliver_from_twilio(twilio_params(body))
      assert reply =~ "in touch"

      assert [request] = Bookings.list_pending_booking_requests(business.id)
      assert request.availability_text == "anytime Thursday"
      assert request.booking_link_id == link.id

      assert [%{start: ~U[2026-06-18 12:00:00Z], end: ~U[2026-06-18 21:00:00Z]}] =
               RompCrm.Bookings.BookingRequest.parsed_windows(request)
    end
  end

  describe "no active booking" do
    test "returns :ignore when client has no active links" do
      params = %{"Body" => "hello?", "From" => "+19999999999", "MessageSid" => "SMx"}
      assert :ignore = CustomerBookingProcessor.deliver_from_twilio(params)
    end
  end

  describe "multi-business collision" do
    setup %{} do
      other_user = user_fixture()
      other_business = business_fixture(%{owner_user: other_user, name: "Dave's Electrical"})

      {:ok, other_link} =
        Bookings.create_booking_link(%{
          business_id: other_business.id,
          technician_user_id: other_user.id,
          job_type_label: "panel upgrade",
          client_phone_normalized: @client_phone
        })

      %{other_business: other_business, other_link: other_link}
    end

    test "ambiguous reply asks for clarification and writes nothing", %{
      business: business,
      other_business: other_business
    } do
      body =
        "STUB_CLARIFY " <>
          Jason.encode!(%{
            "reply_sms" =>
              "It looks like you're scheduling with both Green Mountain Plumbing and Dave's Electrical — which is Tuesday for?"
          })

      assert {:ok, reply} = CustomerBookingProcessor.deliver_from_twilio(twilio_params(body))
      assert reply =~ "which is Tuesday for?"

      # No bookings or requests written under ambiguity
      assert Bookings.list_pending_booking_requests(business.id) == []
      assert Bookings.list_pending_booking_requests(other_business.id) == []

      # Exchange recorded on BOTH businesses' client threads
      for biz <- [business, other_business] do
        turns = SmsConversations.list_client_turns_for_ai(biz.id, @client_phone)
        assert Enum.any?(turns, fn {role, _} -> role == :client end)
        assert Enum.any?(turns, fn {role, t} -> role == :assistant and t =~ "which is Tuesday" end)
      end
    end

    test "resolved booking under collision applies to exactly one business", %{
      business: business,
      other_business: other_business,
      link: link
    } do
      body =
        "STUB_BOOK " <>
          Jason.encode!(%{
            "reply_sms" => "Confirmed with Green Mountain Plumbing for Tuesday!",
            "resolved_booking_link_id" => link.id,
            "action" => %{
              "type" => "hard_booking",
              "starts_at" => "2026-06-16T18:00:00Z",
              "ends_at" => "2026-06-16T21:00:00Z"
            }
          })

      assert {:ok, _reply} = CustomerBookingProcessor.deliver_from_twilio(twilio_params(body))

      assert [_] =
               Bookings.list_confirmed_bookings(
                 business.id,
                 ~U[2026-06-16 00:00:00Z],
                 ~U[2026-06-17 00:00:00Z]
               )

      assert Bookings.list_confirmed_bookings(
               other_business.id,
               ~U[2026-06-16 00:00:00Z],
               ~U[2026-06-17 00:00:00Z]
             ) == []
    end

    test "hard booking with no resolved link under collision is treated as ambiguous", %{
      business: business,
      other_business: other_business
    } do
      body =
        "STUB_BOOK " <>
          Jason.encode!(%{
            "reply_sms" => "Booked!",
            "resolved_booking_link_id" => nil,
            "action" => %{
              "type" => "hard_booking",
              "starts_at" => "2026-06-16T18:00:00Z",
              "ends_at" => "2026-06-16T21:00:00Z"
            }
          })

      assert {:ok, reply} = CustomerBookingProcessor.deliver_from_twilio(twilio_params(body))
      assert reply =~ ~r/which/i

      for biz <- [business, other_business] do
        assert Bookings.list_confirmed_bookings(
                 biz.id,
                 ~U[2026-06-16 00:00:00Z],
                 ~U[2026-06-17 00:00:00Z]
               ) == []
      end
    end
  end
end
