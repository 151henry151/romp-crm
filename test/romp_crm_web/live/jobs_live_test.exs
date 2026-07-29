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

  test "print job opens dialog with with/without photos links", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "Print Dialog Client",
        work_description: "Print me"
      })

    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#job-print-modal")

    view
    |> element("#job-row-#{job.id} button[phx-click=\"open_print_job\"]")
    |> render_click()

    assert has_element?(view, "#job-print-modal")
    html = render(view)
    assert html =~ "Print job"
    assert html =~ "With photos"
    assert html =~ "Without photos"
    assert has_element?(view, "#job-print-modal a[href*=\"/jobs/#{job.id}/print\"]", "With photos")
    assert has_element?(view, "#job-print-modal a[href*=\"photos=0\"]", "Without photos")

    view |> element("#job-print-modal button", "Cancel") |> render_click()
    refute has_element?(view, "#job-print-modal")
  end

  test "choosing a print option closes the dialog", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "Print Close Client",
        work_description: "Print me"
      })

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#job-row-#{job.id} button[phx-click=\"open_print_job\"]")
    |> render_click()

    assert has_element?(view, "#job-print-modal")

    view
    |> element("#job-print-modal a[phx-click=\"close_print_job\"]", "Without photos")
    |> render_click()

    refute has_element?(view, "#job-print-modal")
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
