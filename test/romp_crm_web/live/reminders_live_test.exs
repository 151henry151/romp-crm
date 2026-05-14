defmodule RompCrmWeb.RemindersLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders reminders page when subscribed with a business", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user_with_business(%{conn: conn})

    {:ok, _lv, html} = live(conn, ~p"/reminders")

    assert html =~ "Reminders"
    assert html =~ "New reminder"
  end
end
