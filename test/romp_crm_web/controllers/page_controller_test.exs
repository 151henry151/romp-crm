defmodule RompCrmWeb.PageControllerTest do
  use RompCrmWeb.ConnCase

  setup :register_and_log_in_user_with_business

  test "GET / renders jobs dashboard when authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Romp CRM"
    assert html_response(conn, 200) =~ "Job list"
  end
end
