defmodule RompCrm.GiftsTest do
  use RompCrm.DataCase, async: false

  import RompCrm.AccountsFixtures

  alias RompCrm.Billing
  alias RompCrm.Gifts
  alias RompCrm.Gifts.GiftSubscription
  alias RompCrm.Repo

  setup do
    admin = user_fixture(%{email: "admin.romp.test@example.com"})
    {:ok, admin: admin}
  end

  test "create_and_email inserts gift", %{admin: admin} do
    assert {:ok, gift} =
             Gifts.create_and_email(
               admin,
               %{
                 recipient_email: "gift.recipient@example.com",
                 duration_days: 14,
                 admin_message: "Enjoy"
               },
               fn tok -> "https://example.test/redeem/#{tok}" end
             )

    assert gift.recipient_email == "gift.recipient@example.com"
    assert gift.duration_days == 14
    assert is_nil(gift.redeemed_at)
  end

  test "apply_after_registration activates pending paywall user", %{admin: admin} do
    recipient = "pending_gift@example.com"

    {:ok, gift} =
      Gifts.create_and_email(
        admin,
        %{recipient_email: recipient, duration_days: 7, admin_message: nil},
        fn _ -> "https://example.test/x" end
      )

    {:ok, user} =
      %RompCrm.Accounts.User{}
      |> RompCrm.Accounts.User.email_changeset(%{email: recipient}, validate_unique: false)
      |> Repo.insert()

    {:ok, user} =
      user
      |> Ecto.Changeset.change(subscription_status: "pending_payment")
      |> Repo.update()

    assert {:ok, user} = Gifts.apply_after_registration(user, gift.token)
    assert user.subscription_status == "active"
    assert %DateTime{} = user.gift_access_until
    assert Billing.subscription_active?(user)

    gift = Repo.get!(GiftSubscription, gift.id)
    assert %DateTime{} = gift.redeemed_at
  end
end
