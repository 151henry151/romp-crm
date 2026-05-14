defmodule RompCrmWeb.GiftRedeemControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Gifts
  alias RompCrm.Repo

  test "GET /gift/redeem/:token redirects to /gift/claim/:token", %{conn: conn} do
    conn = get(conn, ~p"/gift/redeem/abc123")
    assert redirected_to(conn) == ~p"/gift/claim/abc123"
  end

  test "GET /gift/claim/:token for new recipient creates account, redeems, and logs in", %{conn: conn} do
    admin = user_fixture()
    recipient = "gift_claim_new@example.com"

    {:ok, gift} =
      Gifts.create_and_email(
        admin,
        %{recipient_email: recipient, duration_days: 7, admin_message: nil},
        fn _t -> "https://example.test/x" end
      )

    refute Accounts.get_user_by_email(recipient)

    conn = get(conn, ~p"/gift/claim/#{gift.token}")

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
    assert conn.assigns.flash["info"] =~ "Welcome"

    user = Accounts.get_user_by_email(recipient)
    assert user
    assert %DateTime{} = Repo.get!(Gifts.GiftSubscription, gift.id).redeemed_at
  end

  test "GET /gift/claim/:token for existing recipient sets return_to and redirects to log in", %{conn: conn} do
    admin = user_fixture()
    recipient = "gift_claim_existing@example.com"
    _ = user_fixture(%{email: recipient})

    {:ok, gift} =
      Gifts.create_and_email(
        admin,
        %{recipient_email: recipient, duration_days: 7, admin_message: nil},
        fn _t -> "https://example.test/x" end
      )

    conn = get(conn, ~p"/gift/claim/#{gift.token}")

    assert redirected_to(conn) ==
             ~p"/users/log-in?#{[email: recipient, after_gift: "1"]}"

    assert get_session(conn, :user_return_to) == ~p"/gift/claim/#{gift.token}"
    refute get_session(conn, :user_token)
  end

  test "GET /gift/claim/:token when logged in as recipient redeems without extra step", %{conn: conn} do
    admin = user_fixture()
    recipient = "gift_claim_logged_in@example.com"
    user = user_fixture(%{email: recipient})

    {:ok, gift} =
      Gifts.create_and_email(
        admin,
        %{recipient_email: recipient, duration_days: 7, admin_message: nil},
        fn _t -> "https://example.test/x" end
      )

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/gift/claim/#{gift.token}")

    assert redirected_to(conn) == ~p"/"
    assert conn.assigns.flash["info"] =~ "Gift applied"
    assert %DateTime{} = Repo.get!(Gifts.GiftSubscription, gift.id).redeemed_at
  end

  test "GET /gift/claim/:token with invalid token returns 404", %{conn: conn} do
    conn = get(conn, ~p"/gift/claim/no-such-token-#{:crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)}")
    assert conn.status == 404
  end
end
