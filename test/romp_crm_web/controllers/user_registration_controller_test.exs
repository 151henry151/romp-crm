defmodule RompCrmWeb.UserRegistrationControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses
  alias RompCrm.Businesses.{BusinessInvitation}
  alias RompCrm.Repo

  describe "GET /users/register" do
    test "sends no-store headers so cached register HTML cannot stale CSRF tokens", %{conn: conn} do
      conn = get(conn, ~p"/users/register")

      assert get_resp_header(conn, "cache-control") == ["private, no-store, must-revalidate"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
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
