defmodule RompCrmWeb.BusinessSwitchControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses

  test "persists picker choice to the user row and redirects home", %{conn: conn} do
    user = user_fixture()
    {:ok, _a} = Businesses.create_business(user, %{name: "Workspace A"})
    {:ok, b} = Businesses.create_business(user, %{name: "Workspace B"})

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/business/switch", %{"business_id" => Integer.to_string(b.id)})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, "current_business_id") == Integer.to_string(b.id)
    assert Accounts.get_user!(user.id).selected_business_id == b.id
  end

  test "rejects switching to an unrelated workspace", %{conn: conn} do
    stranger = user_fixture()
    owner = user_fixture()
    {:ok, hidden} = Businesses.create_business(owner, %{name: "Private Workspace"})

    conn =
      conn
      |> log_in_user(stranger)
      |> post(~p"/business/switch", %{"business_id" => Integer.to_string(hidden.id)})

    assert redirected_to(conn) == ~p"/businesses"
    refute Accounts.get_user!(stranger.id).selected_business_id == hidden.id
  end
end
