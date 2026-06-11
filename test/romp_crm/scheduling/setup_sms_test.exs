defmodule RompCrm.Scheduling.SetupSmsTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Bookings
  alias RompCrm.Repo
  alias RompCrm.Scheduling.Setup
  alias RompCrm.SmsInboundProcessor

  setup do
    user = user_fixture()
    {:ok, user} = Accounts.update_user_profile(user, %{phone: "+18027349389"})

    user =
      user
      |> Ecto.Changeset.change(scheduling_setup_completed_at: nil, scheduling_prefs_json: nil)
      |> Repo.update!()

    business = business_fixture(%{owner_user: user, name: "Setup Test Plumbing"})
    %{user: user, business: business}
  end

  test "booking initiate triggers setup before texting customer", %{user: user, business: business} do
    payload =
      Jason.encode!(%{
        "assistant_sms" => "Texting Bob.",
        "booking_actions" => [
          %{
            "intent" => "initiate",
            "client_name" => "Bob Smith",
            "phone" => "802-530-0293",
            "job_type_label" => "sink replacement",
            "duration_min_minutes" => 90,
            "duration_max_minutes" => 120
          }
        ]
      })

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "STUB_JSON " <> payload,
               delivery: :in_app
             )

    assert reply =~ "one-time scheduling setup"
    assert Bookings.active_links_for_client_phone("18025300293") == []
    assert Setup.active_session?(business.id, user.phone_normalized)
  end

  test "completing setup replays held booking initiate", %{user: user, business: business} do
    held = Setup.held_intent_for_booking_initiate(%{
      client_name: "Bob Smith",
      phone: "802-530-0293",
      job_type_label: "sink replacement",
      duration_min_minutes: 90,
      duration_max_minutes: 120
    })

    Setup.start!(business.id, user.id, user.phone_normalized, held)

    assert {:ok, _} =
             SmsInboundProcessor.process(
               user,
               business.id,
               "Mon-Fri 8am-5pm, option B offer times first",
               delivery: :in_app
             )

    assert {:ok, reply} =
             SmsInboundProcessor.process(user, business.id, "skip", delivery: :in_app)

    assert reply =~ "saved" or reply =~ "Saved"
    refute Setup.active_session?(business.id, user.phone_normalized)
    assert [_link] = Bookings.active_links_for_client_phone("18025300293")

    refreshed = Repo.get!(RompCrm.Accounts.User, user.id)
    assert refreshed.scheduling_setup_completed_at
  end
end
