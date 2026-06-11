defmodule RompCrmWeb.PublicBookingLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings

  defp setup_link(_ctx) do
    user = user_fixture()
    business = business_fixture(%{owner_user: user, name: "Green Mountain Plumbing"})

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        job_type_label: "toilet flange replacement",
        duration_min_minutes: 120,
        duration_max_minutes: 180,
        client_phone_normalized: "18025300293"
      })

    %{user: user, business: business, link: link}
  end

  setup :setup_link

  test "invalid token shows not-found state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/book/not-a-real-token")
    assert html =~ "link isn&#39;t valid"
  end

  test "expired link shows expired state", %{conn: conn, link: link} do
    {:ok, _} =
      link
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :day))
      |> RompCrm.Repo.update()

    {:ok, _view, html} = live(conn, ~p"/book/#{link.token}")
    assert html =~ "expired"
  end

  test "booked link shows already-booked state", %{conn: conn, link: link} do
    {:ok, _} = Bookings.mark_booking_link(link, "booked")

    {:ok, _view, html} = live(conn, ~p"/book/#{link.token}")
    assert html =~ "already booked"
  end

  test "active link shows business, job type, duration, and open slots", %{
    conn: conn,
    link: link
  } do
    {:ok, _view, html} = live(conn, ~p"/book/#{link.token}")

    assert html =~ "Green Mountain Plumbing"
    assert html =~ "toilet flange replacement"
    assert html =~ "2–3 hour"
    assert html =~ "phx-click=\"pick_slot\""
  end

  test "picking a slot and confirming creates the booking", %{
    conn: conn,
    business: business,
    link: link
  } do
    {:ok, view, html} = live(conn, ~p"/book/#{link.token}")

    # Click the first available slot
    [_, start_iso] = Regex.run(~r/phx-value-start="([^"]+)"/, html)
    [_, end_iso] = Regex.run(~r/phx-value-end="([^"]+)"/, html)
    render_click(view, "pick_slot", %{"start" => start_iso, "end" => end_iso})

    html = render(view)
    assert html =~ "Confirm"

    view |> element("button[phx-click=\"confirm_slot\"]") |> render_click()

    html = render(view)
    assert html =~ "confirmed"

    assert RompCrm.Repo.reload!(link).status == "booked"

    now = DateTime.utc_now(:second)

    assert [booking] =
             Bookings.list_confirmed_bookings(
               business.id,
               now,
               DateTime.add(now, 30, :day)
             )

    assert booking.booking_link_id == link.id
    assert booking.confirmed_via == "web"
  end

  test "soft availability submission stores a booking request", %{
    conn: conn,
    business: business,
    link: link
  } do
    {:ok, view, _html} = live(conn, ~p"/book/#{link.token}")

    view |> element("button[phx-click=\"show_soft\"]") |> render_click()

    view
    |> form("form[phx-submit=\"submit_soft\"]", %{"availability" => "Anytime Thursday or Friday morning"})
    |> render_submit()

    html = render(view)
    assert html =~ "be in touch"

    assert [request] = Bookings.list_pending_booking_requests(business.id)
    assert request.availability_text == "Anytime Thursday or Friday morning"
    assert request.booking_link_id == link.id
  end
end
