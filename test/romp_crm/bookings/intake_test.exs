defmodule RompCrm.Bookings.IntakeTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.Bookings.Intake
  alias RompCrm.Jobs

  defp setup_link(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})

    {:ok, client} =
      RompCrm.Clients.create_client(%{
        business_id: business.id,
        client_name: "Jasmine Blair",
        phone: "+18027349384"
      })

    {:ok, job} =
      Jobs.create_job(%{
        business_id: business.id,
        client_id: client.id,
        client_name: "Jasmine Blair",
        phone: "+18027349384",
        work_description: "kitchen sink replacement"
      })

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        client_id: client.id,
        job_id: job.id,
        job_type_label: "kitchen sink replacement",
        client_phone_normalized: "18027349384"
      })

    %{business: business, client: client, job: job, link: link}
  end

  setup :setup_link

  describe "snapshot_for_link/1" do
    test "lists missing intake fields", %{link: link} do
      snap = Intake.snapshot_for_link(link)

      assert snap["needs"]["customer_comments"] == true
      assert snap["needs"]["service_address"] == true
      assert snap["needs"]["email"] == true
      # Billing is only asked once a service address exists.
      assert snap["needs"]["billing_address"] == false
      assert snap["needs"]["any"] == true
    end

    test "needs billing confirmation once service address is on file", %{link: link, job: job} do
      {:ok, _} =
        Jobs.update_job(job, %{
          address_line1: "34 Banner Hill Lane",
          city: "Poestenkill",
          state: "NY",
          postal_code: "12140"
        })

      snap = Intake.snapshot_for_link(link)
      assert snap["needs"]["service_address"] == false
      assert snap["needs"]["billing_address"] == true
    end

    test "reflects on-file contact details", %{link: link, job: job} do
      {:ok, _} =
        Jobs.update_job(job, %{
          customer_comments: "Faucet leaks when I turn it to hot",
          address_line1: "34 Banner Hill Lane",
          city: "Poestenkill",
          state: "NY",
          postal_code: "12140",
          client_email: "jasmine@example.com"
        })

      {:ok, link} = Bookings.mark_intake_flag(link, "billing_confirmed", true)
      snap = Intake.snapshot_for_link(link)

      assert snap["needs"]["customer_comments"] == false
      assert snap["needs"]["service_address"] == false
      assert snap["needs"]["email"] == false
      assert snap["needs"]["billing_address"] == false
      assert snap["needs"]["any"] == false
      assert snap["on_file"]["service_address"] =~ "34 Banner Hill Lane"
      assert snap["on_file"]["email"] == "jasmine@example.com"
      assert snap["on_file"]["customer_comments"] =~ "Faucet leaks"
    end
  end

  describe "apply_updates/2" do
    test "stores verbatim customer comments and contact details on the job", %{
      link: link,
      job: job,
      business: business
    } do
      updates = %{
        "customer_comments" => "Upstairs shower valve stuck",
        "address" => "54 Barn Hill Rd, Shoreham VT",
        "client_email" => "jasmine@example.com",
        "billing_same_as_service" => true
      }

      assert {:ok, updated_link, updated_job} = Intake.apply_updates(link, updates)
      assert updated_link.job_id == job.id
      assert updated_job.customer_comments == "Upstairs shower valve stuck"
      assert updated_job.client_email == "jasmine@example.com"
      assert updated_job.address_line1 =~ "54 Barn Hill"
      assert updated_job.billing_address_different == false
      assert Bookings.intake_flag?(updated_link, "billing_confirmed")

      client = RompCrm.Clients.get_client!(updated_job.client_id, business.id)
      assert client.client_email == "jasmine@example.com"
      assert client.address_line1 =~ "54 Barn Hill"
    end

    test "creates a job when the link has none yet", %{link: link, business: business, client: client} do
      {:ok, link} =
        Bookings.create_booking_link(%{
          business_id: business.id,
          technician_user_id: link.technician_user_id,
          client_id: client.id,
          job_id: nil,
          job_type_label: "toilet replacement",
          client_phone_normalized: "18027349384"
        })

      assert {:ok, updated_link, job} =
               Intake.apply_updates(link, %{"customer_comments" => "I want you to replace my toilet"})

      assert updated_link.job_id == job.id
      assert job.customer_comments == "I want you to replace my toilet"
      assert job.work_description == "toilet replacement"
    end

    test "stores a different billing address", %{link: link, job: job} do
      {:ok, _} =
        Jobs.update_job(job, %{
          address_line1: "34 Banner Hill Lane",
          city: "Poestenkill",
          state: "NY",
          postal_code: "12140"
        })

      assert {:ok, _link, updated_job} =
               Intake.apply_updates(link, %{
                 "billing_address_different" => true,
                 "billing_address" => "PO Box 12, Albany NY 12207"
               })

      assert updated_job.billing_address_different == true
      assert updated_job.billing_address_line1 =~ "PO Box"

      assert Bookings.intake_flag?(
               Bookings.get_booking_link!(link.id),
               "billing_confirmed"
             )
    end
  end
end
