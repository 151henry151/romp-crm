defmodule RompCrm.Bookings.OrchestratorTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.Bookings.Orchestrator
  alias RompCrm.Clients
  alias RompCrm.SmsConversations

  defp setup_business(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user, name: "Green Mountain Plumbing"})
    %{user: user, business: business, ctx: %{business_id: business.id, user_id: user.id, message_sid: "SMtest"}}
  end

  setup :setup_business

  describe "booking_initiate" do
    test "creates client, link, and first SMS thread message", %{ctx: ctx, business: business} do
      op =
        {:booking_initiate,
         %{
           client_id: nil,
           client_name: "Bob Smith",
           phone: "802-530-0293",
           job_id: nil,
           job_type_label: "toilet flange replacement",
           duration_min_minutes: 120,
           duration_max_minutes: 180
         }}

      assert {:ok, [{:ok, summary}]} = Orchestrator.run_operations([op], ctx)
      assert summary =~ "Bob Smith"

      [link] = Bookings.active_links_for_client_phone("18025300293")
      assert link.business_id == business.id
      assert link.job_type_label == "toilet flange replacement"
      assert link.duration_min_minutes == 120

      client = Clients.get_client!(link.client_id, business.id)
      assert client.client_name == "Bob Smith"

      turns = SmsConversations.list_client_turns_for_ai(business.id, "18025300293")
      assert [{:assistant, first_sms}] = turns
      assert first_sms =~ "Green Mountain Plumbing"
      assert first_sms =~ "toilet flange replacement"
      assert first_sms =~ "2–3 hour"
      assert first_sms =~ link.token
    end

    test "reuses an existing client matched by id", %{ctx: ctx, business: business} do
      {:ok, client} =
        Clients.create_client(%{
          business_id: business.id,
          client_name: "Maria Lopez",
          phone: "+18025550101"
        })

      op =
        {:booking_initiate,
         %{
           client_id: client.id,
           client_name: "Maria",
           phone: "8025550101",
           job_id: nil,
           job_type_label: "kitchen faucet replacement",
           duration_min_minutes: 90,
           duration_max_minutes: 120
         }}

      assert {:ok, [{:ok, _}]} = Orchestrator.run_operations([op], ctx)

      [link] = Bookings.active_links_for_client_phone("18025550101")
      assert link.client_id == client.id
      assert Repo.aggregate(RompCrm.Clients.Client, :count) == 1
    end

    test "links the booking to a job created in the same message and reuses its client", %{
      ctx: ctx,
      business: business
    } do
      {:ok, job} =
        RompCrm.Jobs.create_job(%{
          business_id: business.id,
          client_name: "Jasmine Blair",
          phone: "8027349384",
          work_description: "replace kitchen sink"
        })

      {:ok, job} =
        Clients.finalize_job_client_link(job, %{
          "client_name" => "Jasmine Blair",
          "phone" => "8027349384"
        })

      job = RompCrm.Jobs.get_job!(job.id, business.id)
      assert is_integer(job.client_id)

      op =
        {:booking_initiate,
         %{
           client_id: nil,
           client_name: "Jasmine Blair",
           phone: "8027349384",
           job_id: nil,
           job_type_label: "kitchen sink replacement",
           duration_min_minutes: 120,
           duration_max_minutes: 180
         }}

      ctx = Map.put(ctx, :created_jobs, [job])

      assert {:ok, [{:booking_done, _}]} = Orchestrator.run_operations([op], ctx)

      [link] = Bookings.active_links_for_client_phone("18027349384")
      assert link.job_id == job.id
      assert link.client_id == job.client_id
      assert Repo.aggregate(RompCrm.Clients.Client, :count) == 1
    end

    test "reuses an existing client matched by phone when no ids are given", %{
      ctx: ctx,
      business: business
    } do
      {:ok, client} =
        Clients.create_client(%{
          business_id: business.id,
          client_name: "Maria Lopez",
          phone: "+18025550101"
        })

      op =
        {:booking_initiate,
         %{
           client_id: nil,
           client_name: "Maria Lopez",
           phone: "802-555-0101",
           job_id: nil,
           job_type_label: "kitchen faucet replacement",
           duration_min_minutes: 90,
           duration_max_minutes: 120
         }}

      assert {:ok, [{:booking_done, _}]} = Orchestrator.run_operations([op], ctx)

      [link] = Bookings.active_links_for_client_phone("18025550101")
      assert link.client_id == client.id
      assert Repo.aggregate(RompCrm.Clients.Client, :count) == 1
    end

    test "first SMS mentions concrete openings", %{ctx: ctx, business: business} do
      op =
        {:booking_initiate,
         %{
           client_id: nil,
           client_name: "Bob Smith",
           phone: "802-530-0293",
           job_id: nil,
           job_type_label: "toilet flange replacement",
           duration_min_minutes: 120,
           duration_max_minutes: 180
         }}

      assert {:ok, [{:booking_done, _}]} = Orchestrator.run_operations([op], ctx)

      turns = SmsConversations.list_client_turns_for_ai(business.id, "18025300293")
      assert [{:assistant, first_sms}] = turns
      assert first_sms =~ "openings"
      assert first_sms =~ ~r/\d{1,2}:\d{2} (AM|PM)/
    end

    test "invalid phone is skipped with reason", %{ctx: ctx} do
      op =
        {:booking_initiate,
         %{
           client_id: nil,
           client_name: "Bad Phone",
           phone: "12",
           job_id: nil,
           job_type_label: "x",
           duration_min_minutes: 60,
           duration_max_minutes: 60
         }}

      assert {:ok, [{:skipped, :invalid_phone}]} = Orchestrator.run_operations([op], ctx)
      assert Bookings.active_links_for_client_phone("12") == []
    end
  end

  describe "booking_update_duration" do
    test "updates estimate on a link in this business", %{ctx: ctx, business: business, user: user} do
      {:ok, link} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: user.id,
          job_type_label: "drain snake"
        })

      op = {:booking_update_duration, link.id, 30, 60}
      assert {:ok, [{:ok, _}]} = Orchestrator.run_operations([op], ctx)

      reloaded = Bookings.get_booking_link!(link.id)
      assert reloaded.duration_min_minutes == 30
      assert reloaded.duration_max_minutes == 60
    end

    test "link from another business is skipped", %{ctx: ctx} do
      other_user = user_fixture()
      other_business = business_fixture(%{owner_user: other_user})

      {:ok, foreign} =
        Bookings.create_booking_link(%{
          business_id: other_business.id,
          technician_user_id: other_user.id,
          job_type_label: "panel"
        })

      op = {:booking_update_duration, foreign.id, 30, 60}
      assert {:ok, [{:skipped, :not_found}]} = Orchestrator.run_operations([op], ctx)
    end
  end

  describe "booking_confirm_soft" do
    test "converts request to booking and texts the client", %{
      ctx: ctx,
      business: business,
      user: user
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

      op = {:booking_confirm_soft, request.id, ~U[2026-06-18 14:00:00Z], ~U[2026-06-18 17:00:00Z]}
      assert {:ok, [{:ok, summary}]} = Orchestrator.run_operations([op], ctx)
      assert summary =~ "confirmed"

      assert Repo.reload!(request).status == "converted"
      assert Repo.reload!(link).status == "booked"

      turns = SmsConversations.list_client_turns_for_ai(business.id, "18025550123")
      assert Enum.any?(turns, fn {role, body} -> role == :assistant and body =~ "confirmed" end)
    end
  end

  describe "booking_cancel" do
    test "cancels a booking in this business", %{ctx: ctx, business: business, user: user} do
      {:ok, booking} =
        Bookings.create_booking(%{
          business_id: business.id,
          technician_user_id: user.id,
          starts_at: ~U[2026-06-18 14:00:00Z],
          ends_at: ~U[2026-06-18 16:00:00Z]
        })

      op = {:booking_cancel, booking.id, "customer request"}
      assert {:ok, [{:ok, _}]} = Orchestrator.run_operations([op], ctx)
      assert Bookings.get_booking!(booking.id).status == "cancelled"
    end
  end
end
