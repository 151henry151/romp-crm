defmodule RompCrmWeb.UserRegistrationControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses
  alias RompCrm.Businesses.{BusinessInvitation}
  alias RompCrm.Repo
  alias RompCrmWeb.CardlessTrialToken

  defp with_subscription_paywall_enabled(fun) do
    previous = Application.get_env(:romp_crm, :subscription_paywall_enabled)
    Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

    try do
      fun.()
    after
      if previous == nil do
        Application.delete_env(:romp_crm, :subscription_paywall_enabled)
      else
        Application.put_env(:romp_crm, :subscription_paywall_enabled, previous)
      end
    end
  end

  describe "GET /users/register" do
    test "sends no-store headers so cached register HTML cannot stale CSRF tokens", %{conn: conn} do
      conn = get(conn, ~p"/users/register")

      assert get_resp_header(conn, "cache-control") == ["private, no-store, must-revalidate"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
    end

    test "redirects to gift claim when gift query is a pending token", %{conn: conn} do
      admin = user_fixture()

      {:ok, gift} =
        RompCrm.Gifts.create_and_email(
          admin,
          %{
            recipient_email: "gift_reg_redirect@example.com",
            duration_days: 14,
            admin_message: nil
          },
          fn _t -> "https://example.test/x" end
        )

      conn = get(conn, ~p"/users/register?#{[gift: gift.token]}")
      assert redirected_to(conn) == ~p"/gift/claim/#{gift.token}"
    end

    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ ~p"/users/log-in"
      assert response =~ ~p"/users/register"
    end

    test "prefills email from query params", %{conn: conn} do
      conn = get(conn, ~p"/users/register?#{[email: "invitee@example.com"]}")
      response = html_response(conn, 200)

      assert response =~ ~s(value="invitee@example.com")
    end

    test "with pending invitation omits billing plan UI", %{conn: conn} do
      inviter = user_fixture()
      {:ok, business} = Businesses.create_business(inviter, %{name: "Session Invite Biz"})
      email = "pending-invite-ui@example.com"
      %{raw_token: raw} = create_invitation_record!(business, inviter, email)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session("pending_invitation_token", raw)
        |> get(~p"/users/register")

      response = html_response(conn, 200)
      refute response =~ "Billing plan"
      assert response =~ "team invitation"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end

    test "paywall enabled shows cardless trial UI without signed t param", %{conn: conn} do
      with_subscription_paywall_enabled(fn ->
        conn = get(conn, ~p"/users/register")
        body = html_response(conn, 200)
        refute body =~ "Billing plan"
        assert body =~ "no credit card"
        assert body =~ "30"
        assert get_session(conn, :cardless_trial_signup) == true
      end)
    end

    test "valid signed t still enables cardless trial UI when paywall enabled", %{conn: conn} do
      with_subscription_paywall_enabled(fn ->
        t = CardlessTrialToken.sign()
        conn = get(conn, ~p"/users/register?#{[t: t]}")
        body = html_response(conn, 200)
        refute body =~ "Billing plan"
        assert get_session(conn, :cardless_trial_signup) == true
      end)
    end

    test "invalid t shows flash and does not set cardless session when paywall enabled", %{conn: conn} do
      with_subscription_paywall_enabled(fn ->
        conn = get(conn, ~p"/users/register?#{[t: "not-a-valid-token"]}")
        _body = html_response(conn, 200)
        assert conn.assigns.flash["error"] =~ "promotional link"
        refute get_session(conn, :cardless_trial_signup)
      end)
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "with pending invitation registers invited_member without subscription billing", %{
      conn: conn
    } do
      inviter = user_fixture()
      {:ok, business} = Businesses.create_business(inviter, %{name: "Post Invite Biz"})
      email = "invite-register@example.com"
      %{raw_token: raw} = create_invitation_record!(business, inviter, email)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session("pending_invitation_token", raw)

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert conn.assigns.flash["info"] =~ "no PayPal subscription needed"

      user = Accounts.get_user_by_email(email)
      assert user.subscription_status == "invited_member"
      refute user.may_create_business
    end

    @tag :capture_log
    test "creates account but does not log in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"

      assert conn.assigns.flash["info"] =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end

    @tag :capture_log
    test "cardless trial signup sets gift_access_until and emails magic link when paywall enabled", %{
      conn: conn
    } do
      with_subscription_paywall_enabled(fn ->
        t = CardlessTrialToken.sign()
        email = unique_user_email()

        conn =
          conn
          |> get(~p"/users/register?#{[t: t]}")
          |> post(~p"/users/register", %{
            "user" => valid_user_attributes(email: email)
          })

        assert redirected_to(conn) == ~p"/users/log-in"
        assert conn.assigns.flash["info"] =~ "30 days"

        user = Accounts.get_user_by_email(email)
        assert user.subscription_status == "pending_payment"
        assert %DateTime{} = user.gift_access_until
        assert DateTime.after?(user.gift_access_until, DateTime.utc_now(:second))
        refute get_session(conn, :cardless_trial_signup)
      end)
    end

    test "standard signup gets cardless trial without signed t param", %{conn: conn} do
      with_subscription_paywall_enabled(fn ->
        email = unique_user_email()

        conn =
          post(conn, ~p"/users/register", %{
            "user" => valid_user_attributes(email: email)
          })

        assert redirected_to(conn) == ~p"/users/log-in"
        assert conn.assigns.flash["info"] =~ "30 days"
        assert conn.assigns.flash["info"] =~ "no credit card"

        user = Accounts.get_user_by_email(email)
        assert %DateTime{} = user.gift_access_until
        assert DateTime.after?(user.gift_access_until, DateTime.utc_now(:second))
      end)
    end

    test "duplicate pending paywall email without gift trial redirects to subscribe", %{conn: conn} do
      with_subscription_paywall_enabled(fn ->
        email = unique_user_email()
        assert {:ok, _} = Accounts.register_user(valid_user_attributes(email: email))

        conn =
          post(conn, ~p"/users/register", %{
            "user" => valid_user_attributes(email: email)
          })

        assert redirected_to(conn) == ~p"/subscribe"
        assert conn.assigns.flash["info"] =~ "subscription page"
      end)
    end

    test "duplicate signup with active gift trial resends magic link instead of PayPal", %{conn: conn} do
      with_subscription_paywall_enabled(fn ->
        email = unique_user_email()
        assert {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
        assert {:ok, _} = Accounts.apply_cardless_promo_trial(user, 30)

        conn =
          post(conn, ~p"/users/register", %{
            "user" => valid_user_attributes(email: email)
          })

        assert redirected_to(conn) == ~p"/users/log-in"
        assert conn.assigns.flash["info"] =~ "already started"
        assert conn.assigns.flash["info"] =~ "sign-in link"
        refute conn.assigns.flash["info"] =~ "PayPal"
      end)
    end
  end

  defp create_invitation_record!(business, inviter, email) do
    raw_token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    invitation =
      %BusinessInvitation{}
      |> BusinessInvitation.changeset(%{
        business_id: business.id,
        invited_by_user_id: inviter.id,
        email: String.downcase(String.trim(email)),
        token_hash: BusinessInvitation.hash_raw_token(raw_token)
      })
      |> Repo.insert!()

    %{raw_token: raw_token, invitation: invitation}
  end
end
