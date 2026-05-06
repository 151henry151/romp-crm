defmodule JgsCrmWeb.PageControllerTest do
  use JgsCrmWeb.ConnCase

  setup :register_and_log_in_user

  test "GET / renders jobs dashboard when authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "JGS Mechanical"
    assert html_response(conn, 200) =~ "Customer & Job Tracker"
  end
end
