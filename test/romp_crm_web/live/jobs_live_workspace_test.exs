defmodule RompCrmWeb.JobsLiveWorkspaceTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, _a} = Businesses.create_business(user, %{name: "First Workspace"})
    {:ok, b} = Businesses.create_business(user, %{name: "Second Workspace"})
    conn = log_in_user(conn, user)

    %{conn: conn, user: user, biz_b: b}
  end

  test "Jobs list uses persisted workspace when session omits current_business_id", %{
    conn: conn,
    user: user,
    biz_b: b
  } do
    assert {:ok, _} = Accounts.put_jobs_workspace_selection(user, b.id)

    _job =
      job_fixture(%{
        business_id: b.id,
        client_name: "Visible When B Is Selected"
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Visible When B Is Selected"
  end
end
