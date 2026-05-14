defmodule RompCrmWeb.JobsLiveDefaultWorkspaceTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.AccountsFixtures

  alias RompCrm.{Accounts, Businesses}

  test "mounting jobs creates default workspace when user has none", %{conn: conn} do
    user = user_fixture()
    assert Businesses.list_businesses_for_user(user) == []

    conn = log_in_user(conn, user)
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "All"
    user = Accounts.get_user!(user.id)
    assert [%{name: "My workspace"}] = Businesses.list_businesses_for_user(user)
    assert render(view) =~ "All"
  end
end
