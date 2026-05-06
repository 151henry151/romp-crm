defmodule JgsCrmWeb.JobsLiveTest do
  use JgsCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import JgsCrm.JobsFixtures

  setup :register_and_log_in_user

  test "clicking a row toggles expanded details", %{conn: conn} do
    job =
      job_fixture(%{
        client_name: "Angela Brande",
        address: "42 Maple St",
        phone: "802-555-0101",
        work_description: "Bathroom remodel follow-up",
        referred_by: "Sara Grey",
        next_action: "Call Thursday",
        notes: "Detailed Notes 123"
      })

    {:ok, view, _html} = live(conn, ~p"/")

    refute render(view) =~ "Detailed Notes 123"

    view
    |> element("#job-row-#{job.id}")
    |> render_click()

    assert render(view) =~ "Detailed Notes 123"
    assert render(view) =~ "42 Maple St"

    view
    |> element("#job-row-#{job.id}")
    |> render_click()

    refute render(view) =~ "Detailed Notes 123"
  end
end
