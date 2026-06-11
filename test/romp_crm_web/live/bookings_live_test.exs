defmodule RompCrmWeb.BookingsLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RompCrm.Bookings
  alias RompCrm.Repo

  setup %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user_with_business(%{conn: conn})

    business =
      user |> RompCrm.Businesses.list_businesses_for_user() |> List.first()

    {:ok, client} =
      RompCrm.Clients.create_client(%{
        business_id: business.id,
        client_name: "Pat Caller",
        phone: "+18025551234"
      })

    %{conn: conn, user: user, business: business, client: client}
  end

  defp create_link(business, user, client) do
    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        client_id: client.id,
        job_type_label: "Water heater swap",
        duration_min_minutes: 120,
        duration_max_minutes: 180,
        client_phone_normalized: "8025551234"
      })

    link
  end

  test "renders empty state", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/bookings")

    assert html =~ "Bookings"
    assert html =~ "Nothing waiting on you"
    assert html =~ "No open links"
    assert html =~ "No upcoming confirmed bookings"
  end

  test "shows open links and supports duration edit and cancel", %{
    conn: conn,
    user: user,
    business: business,
    client: client
  } do
    link = create_link(business, user, client)

    {:ok, lv, html} = live(conn, ~p"/bookings")
    assert html =~ "Pat Caller"
    assert html =~ "Water heater swap"

    lv |> element("#link-#{link.id} button", "Edit duration") |> render_click()

    lv
    |> element("#link-#{link.id} form")
    |> render_submit(%{"link_id" => link.id, "min_minutes" => "60", "max_minutes" => "90"})

    updated = Repo.reload!(link)
    assert updated.duration_min_minutes == 60
    assert updated.duration_max_minutes == 90

    lv |> element("#link-#{link.id} button", "Cancel link") |> render_click()
    assert Repo.reload!(link).status == "cancelled"
    refute render(lv) =~ "Water heater swap"
  end

  test "confirms a soft-availability request and texts the client", %{
    conn: conn,
    user: user,
    business: business,
    client: client
  } do
    link = create_link(business, user, client)

    {:ok, request} =
      Bookings.create_booking_request(%{
        business_id: business.id,
        technician_user_id: user.id,
        booking_link_id: link.id,
        client_id: client.id,
        availability_text: "Any weekday after 2pm",
        job_type_label: "Water heater swap",
        duration_min_minutes: 120,
        duration_max_minutes: 180,
        status: "pending"
      })

    {:ok, lv, html} = live(conn, ~p"/bookings")
    assert html =~ "Any weekday after 2pm"

    lv |> element("#request-#{request.id} button", "Pick a time") |> render_click()

    lv
    |> element("#request-#{request.id} form")
    |> render_submit(%{
      "request_id" => request.id,
      "date" => "2026-06-22",
      "time" => "14:00",
      "duration_minutes" => "120"
    })

    assert Repo.reload!(request).status == "converted"
    assert Repo.reload!(link).status == "booked"

    html = render(lv)
    assert html =~ "Upcoming bookings"
    assert html =~ "Pat Caller"
    refute html =~ "Any weekday after 2pm"
  end

  test "dismisses a request", %{conn: conn, user: user, business: business, client: client} do
    {:ok, request} =
      Bookings.create_booking_request(%{
        business_id: business.id,
        technician_user_id: user.id,
        client_id: client.id,
        availability_text: "Mornings only",
        status: "pending"
      })

    {:ok, lv, _html} = live(conn, ~p"/bookings")

    lv |> element("#request-#{request.id} button", "Dismiss") |> render_click()

    assert Repo.reload!(request).status == "cancelled"
    refute render(lv) =~ "Mornings only"
  end

  test "cancels an upcoming booking", %{
    conn: conn,
    user: user,
    business: business,
    client: client
  } do
    link = create_link(business, user, client)

    {:ok, booking} =
      Bookings.create_booking(%{
        business_id: business.id,
        technician_user_id: user.id,
        booking_link_id: link.id,
        client_id: client.id,
        starts_at: DateTime.add(DateTime.utc_now(:second), 2, :day),
        ends_at: DateTime.add(DateTime.utc_now(:second), 2, :day) |> DateTime.add(2, :hour),
        status: "confirmed",
        confirmed_via: "web"
      })

    {:ok, lv, html} = live(conn, ~p"/bookings")
    assert html =~ "booked via web"

    lv |> element("#booking-#{booking.id} button", "Cancel") |> render_click()

    assert Repo.reload!(booking).status == "cancelled"
    assert render(lv) =~ "No upcoming confirmed bookings"
  end
end
