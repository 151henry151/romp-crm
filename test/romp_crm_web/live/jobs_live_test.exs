defmodule RompCrmWeb.JobsLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.JobsFixtures

  alias RompCrm.Businesses

  setup :register_and_log_in_user_with_business

  test "clicking a row toggles expanded details", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "Angela Brande",
        address: "42 Maple St",
        phone: "802-555-0101",
        work_description: "Bathroom remodel follow-up",
        referred_by: "Sara Grey",
        next_action: "Call Thursday",
        notes: "Detailed Notes 123"
      })

    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#job-expand-md-#{job.id}")
    refute has_element?(view, "#job-expand-sm-#{job.id}")

    view
    |> element("#job-row-#{job.id}")
    |> render_click()

    assert has_element?(view, "#job-expand-md-#{job.id}")
    assert has_element?(view, "#job-expand-sm-#{job.id}")
    expanded = render(view)
    assert expanded =~ "Detailed Notes 123"

    view
    |> element("#job-row-#{job.id}")
    |> render_click()

    refute has_element?(view, "#job-expand-md-#{job.id}")
    refute has_element?(view, "#job-expand-sm-#{job.id}")
  end

  test "add work item from expanded row", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "Work Item Co",
        work_description: "Initial scope"
      })

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#job-row-#{job.id}") |> render_click()

    view |> element("button[aria-label=\"Add work item\"]") |> render_click()

    assert render(view) =~ "wi-title-"
    assert has_element?(view, "input[name=\"title\"]")
  end
end
