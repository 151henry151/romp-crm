defmodule RompCrm.BillingTest do
  use RompCrm.DataCase

  alias RompCrm.Billing
  alias RompCrm.Repo

  import RompCrm.AccountsFixtures

  describe "cancel_subscription_for_user/1" do
    test "returns not_cancellable when hosted paywall is disabled" do
      user = user_fixture()

      {:ok, user} =
        Repo.update(Ecto.Changeset.change(user, paypal_subscription_id: "I-NOPAYWALL"))

      assert {:error, :not_cancellable} = Billing.cancel_subscription_for_user(user)
    end

    test "returns not_cancellable when subscriber is invited_member" do
      Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

      on_exit(fn ->
        Application.put_env(:romp_crm, :subscription_paywall_enabled, false)
      end)

      user = user_fixture()

      {:ok, user} =
        Repo.update(
          Ecto.Changeset.change(user,
            subscription_status: "invited_member",
            paypal_subscription_id: "I-INVITED",
            may_create_business: false
          )
        )

      assert {:error, :not_cancellable} = Billing.cancel_subscription_for_user(user)
    end

    test "returns not_cancellable when active but PayPal subscription id is absent" do
      Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

      on_exit(fn ->
        Application.put_env(:romp_crm, :subscription_paywall_enabled, false)
      end)

      user = user_fixture()

      {:ok, user} =
        Repo.update(
          Ecto.Changeset.change(user,
            subscription_status: "active",
            paypal_subscription_id: nil
          )
        )

      assert {:error, :not_cancellable} = Billing.cancel_subscription_for_user(user)
    end
  end

  describe "subscription_active?/1" do
    test "returns true for invited_member (team invitation access)" do
      user = user_fixture()
      {:ok, user} =
        user
        |> Ecto.Changeset.change(subscription_status: "invited_member")
        |> Repo.update()

      assert Billing.subscription_active?(user)
    end
  end

  describe "paypal_return_subscription_id/1" do
    test "reads subscription_id" do
      assert Billing.paypal_return_subscription_id(%{"subscription_id" => " I-ABC123 \n"}) ==
               "I-ABC123"
    end

    test "reads subscriptionId (camelCase)" do
      assert Billing.paypal_return_subscription_id(%{"subscriptionId" => "I-XYZ9"}) == "I-XYZ9"
    end

    test "falls back to token when it looks like a subscription id" do
      assert Billing.paypal_return_subscription_id(%{"token" => "I-SUB1"}) == "I-SUB1"
    end

    test "ignores token that does not look like a PayPal subscription id" do
      assert Billing.paypal_return_subscription_id(%{"token" => "EC-123"}) == ""
    end
  end

  describe "finalize_subscription_active/3" do
    setup do
      user = unconfirmed_user_fixture()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(
          paypal_subscription_id: "I-FIXTURE",
          subscription_status: "pending_payment",
          paypal_plan_id: "P-OLD"
        )
        |> Repo.update()

      %{user: user}
    end

    test "activates when status is APPROVED and payer email is absent", %{user: user} do
      payload = %{
        "status" => "APPROVED",
        "plan_id" => "P-NEW"
      }

      assert {:ok, updated} = Billing.finalize_subscription_active(user, "I-FIXTURE", payload)
      assert updated.subscription_status == "active"
      assert updated.paypal_plan_id == "P-NEW"
    end

    test "activates when status is ACTIVE", %{user: user} do
      payload = %{
        "status" => "ACTIVE",
        "subscriber" => %{"email_address" => user.email}
      }

      assert {:ok, updated} = Billing.finalize_subscription_active(user, "I-FIXTURE", payload)
      assert updated.subscription_status == "active"
    end

    test "rejects APPROVAL_PENDING", %{user: user} do
      payload = %{"status" => "APPROVAL_PENDING"}

      assert {:error, {:not_active, "APPROVAL_PENDING"}} =
               Billing.finalize_subscription_active(user, "I-FIXTURE", payload)
    end

    test "activates when PayPal payer email differs from registration email", %{user: user} do
      payload = %{
        "status" => "ACTIVE",
        "subscriber" => %{"email_address" => "different-payer@example.com"}
      }

      assert {:ok, updated} = Billing.finalize_subscription_active(user, "I-FIXTURE", payload)
      assert updated.subscription_status == "active"
    end
  end
end
