defmodule RompCrmWeb.EmployeesLiveTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures
  import RompCrm.EmployeesFixtures

  setup %{conn: conn} do
    user = user_fixture()
    biz = business_fixture(%{owner_user: user})
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user, biz: biz}
  end

  # ── Employee list page ─────────────────────────────────────────────────────

  describe "employees list" do
    test "renders employees table", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/employees")
      assert has_element?(view, "#employees-table")
    end

    test "shows employee rows for existing employees", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry Jones"})
      {:ok, view, _html} = live(conn, ~p"/employees")
      assert has_element?(view, "#employee-row-#{emp.id}")
    end

    test "shows empty state when no employees", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/employees")
      assert has_element?(view, "#employees-empty")
    end

    test "can create a new employee via form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/employees/new")
      assert has_element?(view, "#employee-form")

      view
      |> form("#employee-form", %{
        "employee" => %{
          "name" => "Alice Cooper",
          "title" => "Lead Tech"
        }
      })
      |> render_submit()

      # After push_patch, modal closes and list refreshes
      assert has_element?(view, "#employees-table")
    end

    test "shows validation errors on empty name submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/employees/new")

      view
      |> form("#employee-form", %{"employee" => %{"name" => ""}})
      |> render_submit()

      assert has_element?(view, "#employee-form")
    end

    test "can delete an employee", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})
      {:ok, view, _html} = live(conn, ~p"/employees")

      assert has_element?(view, "#employee-row-#{emp.id}")

      view
      |> element("#delete-employee-#{emp.id}")
      |> render_click()

      refute has_element?(view, "#employee-row-#{emp.id}")
    end
  end

  # ── Employee detail page ───────────────────────────────────────────────────

  describe "employee detail" do
    test "renders employee detail page", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry Jones"})
      {:ok, view, _html} = live(conn, ~p"/employees/#{emp.id}")
      assert has_element?(view, "#employee-info")
      assert has_element?(view, "#employee-time-table")
    end

    test "shows time entry row for completed entry", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

      entry =
        employee_time_entry_fixture(%{
          employee_id: emp.id,
          business_id: biz.id,
          clocked_in_at: ~N[2026-05-11 08:00:00],
          clocked_out_at: ~N[2026-05-11 16:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/employees/#{emp.id}")
      assert has_element?(view, "#emp-entry-#{entry.id}")
      assert has_element?(view, "#emp-entry-dur-#{entry.id}", "8h")
    end

    test "shows lunch deduction in worked time", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

      entry =
        employee_time_entry_fixture(%{
          employee_id: emp.id,
          business_id: biz.id,
          clocked_in_at: ~N[2026-05-11 08:00:00],
          clocked_out_at: ~N[2026-05-11 16:00:00],
          lunch_start_at: ~N[2026-05-11 12:00:00],
          lunch_end_at: ~N[2026-05-11 13:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/employees/#{emp.id}")
      assert has_element?(view, "#emp-entry-dur-#{entry.id}", "7h")
    end

    test "shows in-progress badge when still clocked in", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

      entry =
        employee_time_entry_fixture(%{
          employee_id: emp.id,
          business_id: biz.id,
          clocked_in_at: ~N[2026-05-11 08:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/employees/#{emp.id}")
      assert has_element?(view, "#emp-entry-open-#{entry.id}", "In progress")
    end

    test "shows empty state when no time entries", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})
      {:ok, view, _html} = live(conn, ~p"/employees/#{emp.id}")
      assert has_element?(view, "#employee-time-empty")
    end

    test "shows total label in info card", %{conn: conn, biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

      employee_time_entry_fixture(%{
        employee_id: emp.id,
        business_id: biz.id,
        clocked_in_at: ~N[2026-05-11 08:00:00],
        clocked_out_at: ~N[2026-05-11 10:00:00]
      })

      {:ok, view, _html} = live(conn, ~p"/employees/#{emp.id}")
      assert has_element?(view, "#employee-total", "2h total")
    end
  end
end
