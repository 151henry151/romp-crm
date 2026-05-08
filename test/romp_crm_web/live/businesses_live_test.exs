defmodule RompCrmWeb.BusinessesLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RompCrm.Businesses

  setup context do
    %{conn: conn, user: user} = register_and_log_in_user(context)
    {:ok, b1} = Businesses.create_business(user, %{name: "Default workspace"})
    {:ok, b2} = Businesses.create_business(user, %{name: "Romp Work"})
    %{conn: conn, user: user, biz_a: b1, biz_b: b2}
  end

  test "hides create-business section when user may not create a business", %{conn: conn} do
    user = RompCrm.AccountsFixtures.user_fixture()

    {:ok, user} =
      user
      |> Ecto.Changeset.change(may_create_business: false)
      |> RompCrm.Repo.update()

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/businesses")

    refute html =~ "Create a business"
    assert html =~ "can’t create a new organization"
  end

  test "typing invite email updates only that business's field", %{conn: conn, biz_a: b1, biz_b: b2} do
    {:ok, view, _html} = live(conn, ~p"/businesses")

    render_change(view, "validate_invite", %{
      "invite" => %{"email" => "henry@", "business_id" => to_string(b2.id)}
    })

    html1 =
      view
      |> element("form#invite-#{b1.id}")
      |> render()

    html2 =
      view
      |> element("form#invite-#{b2.id}")
      |> render()

    refute html1 =~ "henry@"
    assert html2 =~ "henry@"
  end
end
