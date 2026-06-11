defmodule RompCrm.SmsInboundRoleRouterTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.SmsInboundRolePrompts
  alias RompCrm.SmsInboundRoleRouter

  setup do
    tech = user_fixture()
    {:ok, tech} = RompCrm.Accounts.update_user_profile(tech, %{phone: "+18024587299"})
    client_user = user_fixture()
    {:ok, client_user} = RompCrm.Accounts.update_user_profile(client_user, %{phone: "+18027349389"})
    business = business_fixture(%{owner_user: tech, name: "Bob's Plumbing"})

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: tech.id,
        job_type_label: "sink repair",
        duration_min_minutes: 90,
        duration_max_minutes: 120,
        client_phone_normalized: "18027349389"
      })

    %{tech: tech, client_user: client_user, business: business, link: link}
  end

  test "defaults dual-role phone to client booking for scheduling replies" do
    assert {:client, params} =
             SmsInboundRoleRouter.route(%{
               "From" => "+18027349389",
               "Body" => "Are there any other times available?"
             })

    assert params["Body"] =~ "other times"
    refute SmsInboundRolePrompts.get("18027349389")
  end

  test "asks disambiguation when dual-role message looks like contractor CRM" do
    assert {:asked_disambiguation, reply} =
             SmsInboundRoleRouter.route(%{
               "From" => "+18027349389",
               "Body" => "Create a new job called website photos"
             })

    assert reply =~ "Bob's Plumbing"
    assert reply =~ "Romp CRM"
    assert SmsInboundRolePrompts.get("18027349389")
  end

  test "remembers scheduling choice after disambiguation prompt", %{client_user: client_user} do
    SmsInboundRolePrompts.store!("18027349389", client_user.id, ["Bob's Plumbing"])

    assert {:client, _} =
             SmsInboundRoleRouter.route(%{
               "From" => "+18027349389",
               "Body" => "scheduling with Bob's Plumbing"
             })

    refute SmsInboundRolePrompts.get("18027349389")
  end

  test "routes registered user without booking links to contractor", %{tech: tech} do
    assert {:contractor, user} =
             SmsInboundRoleRouter.route(%{
               "From" => "+18024587299",
               "Body" => "Any jobs today?"
             })

    assert user.id == tech.id
  end
end
