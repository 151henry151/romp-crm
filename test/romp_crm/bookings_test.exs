defmodule RompCrm.BookingsTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings

  defp setup_business(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business}
  end

  setup :setup_business

  describe "booking links" do
    test "create_booking_link/1 generates a unique token and defaults", %{
      user: user,
      business: business
    } do
      assert {:ok, link} =
               Bookings.create_booking_link(%{
                 business_id: business.id,
                 technician_user_id: user.id,
                 job_type_label: "Toilet flange replacement",
                 duration_min_minutes: 120,
                 duration_max_minutes: 180,
                 client_phone_normalized: "18025300293"
               })

      assert link.status == "pending"
      assert is_binary(link.token) and byte_size(link.token) >= 16
      assert %DateTime{} = link.expires_at

      assert Bookings.get_booking_link_by_token(link.token).id == link.id
    end

    test "get_booking_link_by_token/1 returns nil for unknown token" do
      assert Bookings.get_booking_link_by_token("nope") == nil
    end

    test "active_links_for_client_phone/1 returns pending unexpired links across businesses", %{
      user: user,
      business: business
    } do
      other_user = user_fixture()
      other_business = business_fixture(%{owner_user: other_user})

      phone = "18025550199"

      {:ok, link_a} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Drain snake",
          client_phone_normalized: phone
        })

      {:ok, link_b} =
        Bookings.create_booking_link(%{
          business_id: other_business.id,
          technician_user_id: other_user.id,
          job_type_label: "Panel upgrade",
          client_phone_normalized: phone
        })

      {:ok, expired} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Old link",
          client_phone_normalized: phone,
          expires_at: DateTime.add(DateTime.utc_now(:second), -1, :day)
        })

      {:ok, booked} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Done deal",
          client_phone_normalized: phone
        })

      {:ok, _} = Bookings.mark_booking_link(booked, "booked")

      ids = Bookings.active_links_for_client_phone(phone) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([link_a.id, link_b.id])
      refute expired.id in ids
    end
  end

  describe "bookings" do
    test "create_booking/1 then cancel_booking/1", %{user: user, business: business} do
      assert {:ok, booking} =
               Bookings.create_booking(%{
                 business_id: business.id,
                 technician_user_id: user.id,
                 starts_at: ~U[2026-06-16 14:00:00Z],
                 ends_at: ~U[2026-06-16 16:00:00Z],
                 confirmed_via: "sms"
               })

      assert booking.status == "confirmed"
      assert {:ok, cancelled} = Bookings.cancel_booking(booking)
      assert cancelled.status == "cancelled"
    end

    test "create_booking/1 rejects inverted times", %{user: user, business: business} do
      assert {:error, changeset} =
               Bookings.create_booking(%{
                 business_id: business.id,
                 technician_user_id: user.id,
                 starts_at: ~U[2026-06-16 16:00:00Z],
                 ends_at: ~U[2026-06-16 14:00:00Z]
               })

      assert %{ends_at: ["must be after the start time"]} = errors_on(changeset)
    end
  end

  describe "booking requests (soft availability)" do
    test "create then confirm into a booking marks link booked", %{
      user: user,
      business: business
    } do
      {:ok, link} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Water heater install",
          duration_min_minutes: 180,
          duration_max_minutes: 240,
          client_phone_normalized: "18025550123"
        })

      assert {:ok, request} =
               Bookings.create_booking_request(%{
                 business_id: business.id,
                 technician_user_id: user.id,
                 booking_link_id: link.id,
                 availability_text: "anytime Thursday",
                 job_type_label: link.job_type_label
               })

      assert request.status == "pending"

      assert {:ok, booking} =
               Bookings.confirm_booking_request(request, %{
                 starts_at: ~U[2026-06-18 14:00:00Z],
                 ends_at: ~U[2026-06-18 17:00:00Z],
                 confirmed_via: "technician"
               })

      assert booking.status == "confirmed"
      assert booking.booking_link_id == link.id

      assert Repo.reload!(request).status == "converted"
      assert Repo.reload!(link).status == "booked"
    end
  end

  describe "snapshot_for_sms_ai/1" do
    test "includes active links, pending requests, and upcoming bookings", %{
      user: user,
      business: business
    } do
      {:ok, link} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Drain snake",
          client_phone_normalized: "18025550155"
        })

      {:ok, request} =
        Bookings.create_booking_request(%{
          business_id: business.id,
          technician_user_id: user.id,
          booking_link_id: link.id,
          availability_text: "Thursday afternoon",
          job_type_label: "Drain snake"
        })

      {:ok, booking} =
        Bookings.create_booking(%{
          business_id: business.id,
          technician_user_id: user.id,
          starts_at: DateTime.add(DateTime.utc_now(:second), 2, :day),
          ends_at: DateTime.add(DateTime.utc_now(:second), 2, :day) |> DateTime.add(2, :hour)
        })

      snapshot = Bookings.snapshot_for_sms_ai(business.id)

      assert [%{"booking_link_id" => link_id} | _] = snapshot["active_booking_links"]
      assert link_id == link.id

      assert [%{"booking_request_id" => req_id, "availability_text" => "Thursday afternoon"}] =
               snapshot["pending_booking_requests"]

      assert req_id == request.id

      assert [%{"booking_id" => booking_id}] = snapshot["upcoming_bookings"]
      assert booking_id == booking.id
    end

    test "excludes other businesses and non-pending rows", %{user: user, business: business} do
      other_user = user_fixture()
      other_business = business_fixture(%{owner_user: other_user})

      {:ok, _foreign} =
        Bookings.create_booking_link(%{
          business_id: other_business.id,
          technician_user_id: other_user.id,
          job_type_label: "Foreign"
        })

      {:ok, cancelled} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Cancelled"
        })

      {:ok, _} = Bookings.mark_booking_link(cancelled, "cancelled")

      snapshot = Bookings.snapshot_for_sms_ai(business.id)
      assert snapshot["active_booking_links"] == []
      assert snapshot["pending_booking_requests"] == []
      assert snapshot["upcoming_bookings"] == []
    end
  end

  describe "expire_stale_links/0" do
    test "marks pending links past expiry as expired", %{user: user, business: business} do
      {:ok, stale} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Stale",
          expires_at: DateTime.add(DateTime.utc_now(:second), -1, :hour)
        })

      {:ok, fresh} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "Fresh"
        })

      assert Bookings.expire_stale_links() == 1
      assert Repo.reload!(stale).status == "expired"
      assert Repo.reload!(fresh).status == "pending"
    end
  end
end
