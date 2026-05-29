defmodule RompCrm.SmsPendingJobProposalsTest do
  use RompCrm.DataCase

  alias RompCrm.Jobs
  alias RompCrm.SmsPendingJobProposals

  setup do
    user = RompCrm.AccountsFixtures.user_fixture()
    {:ok, business} = RompCrm.Businesses.create_business(user, %{name: "Proposal Biz"})
    phone = "18024587299"

    proposal = %{
      job_attrs: %{
        client_name: "Jimmy Wang",
        address: "123 Bonehead Drive",
        phone: "8025551212",
        work_description: "Leaking sink faucet",
        status: :lead
      },
      attach_media_urls: []
    }

    {:ok, user: user, business: business, phone: phone, proposal: proposal}
  end

  test "confirmation_message? matches common affirmatives" do
    assert SmsPendingJobProposals.confirmation_message?("CONFIRM")
    assert SmsPendingJobProposals.confirmation_message?("yes please")
    refute SmsPendingJobProposals.confirmation_message?("Dave")
  end

  test "store and apply_pending creates jobs", %{user: user, business: business, phone: phone, proposal: proposal} do
    SmsPendingJobProposals.store!(business.id, user.id, phone, "sms_screenshot", [proposal])

    assert {:ok, results} = SmsPendingJobProposals.apply_pending(business.id, user.id, phone)
    assert Enum.any?(results, &match?({:created, _, _}, &1))

    assert [%{client_name: "Jimmy Wang"}] =
             Jobs.list_jobs(business.id)
             |> Enum.filter(&(&1.client_name == "Jimmy Wang"))

    assert :none = SmsPendingJobProposals.apply_pending(business.id, user.id, phone)
  end
end
