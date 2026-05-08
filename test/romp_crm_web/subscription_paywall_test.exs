defmodule RompCrmWeb.SubscriptionPaywallTest do
  use RompCrmWeb.ConnCase

  import RompCrm.AccountsFixtures

  describe "hosted subscription paywall" do
    setup do
      previous = Application.get_env(:romp_crm, :subscription_paywall_enabled)
      Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

      on_exit(fn ->
        Application.put_env(:romp_crm, :subscription_paywall_enabled, previous)
      end)

      :ok
    end

    test "redirects a logged-in user without an active subscription away from jobs", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = RompCrm.Repo.update(Ecto.Changeset.change(user, subscription_status: "pending_payment"))

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/")

      assert redirected_to(conn) == ~p"/subscribe"
    end
  end
end
