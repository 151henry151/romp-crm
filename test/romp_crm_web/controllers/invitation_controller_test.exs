defmodule RompCrmWeb.InvitationControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses
  alias RompCrm.Businesses.{BusinessInvitation, BusinessMembership}
  alias RompCrm.Repo

  setup %{conn: conn} do
    inviter = user_fixture()
    {:ok, business} = Businesses.create_business(inviter, %{name: "Invite Test Biz"})

    %{conn: conn, inviter: inviter, business: business}
  end

  test "redirects unauthenticated invitees with accounts to login and preserves invitation", %{
    conn: conn,
    inviter: inviter,
    business: business
  } do
    invitee = user_fixture(%{email: "invited@example.com"})
    %{raw_token: raw_token} = create_invitation!(business, inviter, invitee.email)

    conn = get(conn, ~p"/invitations/#{raw_token}")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, "pending_invitation_token") == raw_token
    assert get_session(conn, :user_return_to) == ~p"/invitations/#{raw_token}"
  end

  test "redirects unauthenticated invitees without accounts to register with prefilled email", %{
    conn: conn,
    inviter: inviter,
    business: business
  } do
    email = "new-user@example.com"
    %{raw_token: raw_token} = create_invitation!(business, inviter, email)

    conn = get(conn, ~p"/invitations/#{raw_token}")

    assert redirected_to(conn) == ~p"/users/register?#{[email: email]}"
    assert get_session(conn, "pending_invitation_token") == raw_token
    assert get_session(conn, :user_return_to) == ~p"/invitations/#{raw_token}"
  end

  test "redirects logged in wrong user to login with preserved invitation", %{
    conn: conn,
    inviter: inviter,
    business: business
  } do
    invitee_email = "correct@example.com"
    wrong_user = user_fixture(%{email: "wrong@example.com"})
    %{raw_token: raw_token} = create_invitation!(business, inviter, invitee_email)

    conn =
      conn
      |> log_in_user(wrong_user)
      |> get(~p"/invitations/#{raw_token}")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, "pending_invitation_token") == raw_token
    assert get_session(conn, :user_return_to) == ~p"/invitations/#{raw_token}"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ invitee_email
  end

  test "accepts invitation for logged in matching user", %{
    conn: conn,
    inviter: inviter,
    business: business
  } do
    invitee = user_fixture(%{email: "joiner@example.com"})
    invitation = create_invitation!(business, inviter, invitee.email)

    conn =
      conn
      |> log_in_user(invitee)
      |> get(~p"/invitations/#{invitation.raw_token}")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You joined"
    assert get_session(conn, "current_business_id") == Integer.to_string(business.id)

    assert Accounts.get_user!(invitee.id).selected_business_id == business.id

    assert Repo.get_by(BusinessMembership, business_id: business.id, user_id: invitee.id)
    refute Repo.get(BusinessInvitation, invitation.id)
  end

  defp create_invitation!(business, inviter, email) do
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

    %{id: invitation.id, raw_token: raw_token}
  end
end
