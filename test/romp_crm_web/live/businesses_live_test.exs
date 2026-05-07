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

  test "typing invite email updates only that business's field", %{
    conn: conn,
    biz_a: b1,
    biz_b: b2
  } do
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
