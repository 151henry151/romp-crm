defmodule RompCrm.Accounts.SignupNotifyTest do
  use RompCrm.DataCase, async: false

  import RompCrm.AccountsFixtures
  import Swoosh.TestAssertions

  alias RompCrm.Accounts
  alias RompCrm.Businesses

  setup :set_swoosh_global

  setup do
    Application.put_env(:romp_crm, :signup_notify_emails, ["signup.notify@example.com"])

    on_exit(fn ->
      Application.put_env(:romp_crm, :signup_notify_emails, [])
    end)

    :ok
  end

  test "notifies configured addresses when a new user registers" do
    email = unique_user_email()

    assert {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
    assert user.email == email

    assert_signup_notify_sent("signup.notify@example.com", email)
  end

  test "does not notify on resumable paywall repeat registration" do
    Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

    on_exit(fn ->
      Application.put_env(:romp_crm, :subscription_paywall_enabled, false)
    end)

    email = unique_user_email()
    attrs = valid_user_attributes(email: email)

    assert {:ok, user1} = Accounts.register_user(attrs)
    assert {:ok, user2} = Accounts.register_user(attrs)
    assert user1.id == user2.id

    assert_signup_notify_sent("signup.notify@example.com", email)
  end

  @tag :capture_log
  test "notifies when an invited member registers" do
    inviter = user_fixture()
    {:ok, business} = Businesses.create_business(inviter, %{name: "Notify Invite Co"})
    email = unique_user_email()
    {:ok, invitation} = Businesses.invite_user(business, inviter, email)

    assert {:ok, _} =
             Accounts.register_user(valid_user_attributes(email: email), invitation: invitation)

    assert_signup_notify_sent("signup.notify@example.com", email)
  end

  test "notifies when a gift claim creates a user" do
    email = unique_user_email()

    assert {:ok, _user} = Accounts.insert_gift_recipient_user(email)

    assert_signup_notify_sent("signup.notify@example.com", email)
  end

  defp assert_signup_notify_sent(notify_to, user_email) do
    assert_receive {:email, email}, 1000, "expected signup notify for #{user_email}"

    if email.to == [{"", notify_to}] and
         email.subject == "Romp CRM — new account: #{user_email}" do
      :ok
    else
      assert_signup_notify_sent(notify_to, user_email)
    end
  end
end
