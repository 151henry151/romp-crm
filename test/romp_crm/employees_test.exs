defmodule RompCrm.EmployeesTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.Employees
  alias RompCrm.Employees.{Employee, EmployeeTimeEntry}

  import RompCrm.JobsFixtures
  import RompCrm.EmployeesFixtures

  setup do
    biz = business_fixture()
    {:ok, biz: biz}
  end

  # ── Employee CRUD ─────────────────────────────────────────────────────────

  describe "list_employees/1" do
    test "returns employees for business ordered by name", %{biz: biz} do
      employee_fixture(%{business_id: biz.id, name: "Zoe Smith"})
      employee_fixture(%{business_id: biz.id, name: "Aaron Jones"})

      [first, second] = Employees.list_employees(biz.id)
      assert first.name == "Aaron Jones"
      assert second.name == "Zoe Smith"
    end

    test "does not return employees from other businesses", %{biz: biz} do
      employee_fixture(%{business_id: biz.id})
      other = business_fixture()
      employee_fixture(%{business_id: other.id})

      assert length(Employees.list_employees(biz.id)) == 1
    end
  end

  describe "get_employee!/2" do
    test "returns employee when found", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})
      assert Employees.get_employee!(emp.id, biz.id).name == "Henry"
    end

    test "raises when not found or wrong business", %{biz: biz} do
      assert_raise Ecto.NoResultsError, fn ->
        Employees.get_employee!(999_999, biz.id)
      end
    end
  end

  describe "create_employee/1" do
    test "creates employee with required fields", %{biz: biz} do
      assert {:ok, %Employee{} = emp} =
               Employees.create_employee(%{business_id: biz.id, name: "Henry"})

      assert emp.name == "Henry"
      assert emp.business_id == biz.id
    end

    test "creates employee with optional fields", %{biz: biz} do
      assert {:ok, emp} =
               Employees.create_employee(%{
                 business_id: biz.id,
                 name: "Henry",
                 phone: "8025551234",
                 email: "henry@example.com",
                 title: "Plumber",
                 notes: "Reliable worker"
               })

      assert emp.phone == "8025551234"
      assert emp.title == "Plumber"
    end

    test "returns error when name is missing", %{biz: biz} do
      assert {:error, changeset} = Employees.create_employee(%{business_id: biz.id})
      assert changeset.errors[:name] != nil
    end
  end

  describe "update_employee/2" do
    test "updates employee fields", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})
      assert {:ok, updated} = Employees.update_employee(emp, %{title: "Lead Tech"})
      assert updated.title == "Lead Tech"
    end
  end

  describe "delete_employee/1" do
    test "deletes the employee", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})
      assert {:ok, _} = Employees.delete_employee(emp)
      assert Employees.list_employees(biz.id) == []
    end
  end

  # ── Time entry CRUD ───────────────────────────────────────────────────────

  describe "create_time_entry/1" do
    test "creates a clock-in entry", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

      assert {:ok, %EmployeeTimeEntry{} = entry} =
               Employees.create_time_entry(%{
                 business_id: biz.id,
                 employee_id: emp.id,
                 clocked_in_at: ~N[2026-05-11 08:00:00]
               })

      assert entry.clocked_in_at == ~N[2026-05-11 08:00:00]
      assert entry.clocked_out_at == nil
    end

    test "returns error when clocked_in_at is missing", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})

      assert {:error, cs} =
               Employees.create_time_entry(%{business_id: biz.id, employee_id: emp.id})

      assert cs.errors[:clocked_in_at] != nil
    end
  end

  describe "list_time_entries/2" do
    test "returns entries for employee newest first", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})

      e1 =
        employee_time_entry_fixture(%{
          employee_id: emp.id,
          business_id: biz.id,
          clocked_in_at: ~N[2026-05-11 08:00:00]
        })

      e2 =
        employee_time_entry_fixture(%{
          employee_id: emp.id,
          business_id: biz.id,
          clocked_in_at: ~N[2026-05-12 08:00:00]
        })

      entries = Employees.list_time_entries(emp.id, biz.id)
      assert length(entries) == 2
      assert hd(entries).id == e2.id
    end

    test "does not return entries from other employees", %{biz: biz} do
      emp1 = employee_fixture(%{business_id: biz.id})
      emp2 = employee_fixture(%{business_id: biz.id})
      employee_time_entry_fixture(%{employee_id: emp1.id, business_id: biz.id})
      employee_time_entry_fixture(%{employee_id: emp2.id, business_id: biz.id})

      assert length(Employees.list_time_entries(emp1.id, biz.id)) == 1
    end
  end

  describe "list_all_time_entries/1" do
    test "returns all entries for business with employee preloaded", %{biz: biz} do
      emp1 = employee_fixture(%{business_id: biz.id, name: "Henry"})
      emp2 = employee_fixture(%{business_id: biz.id, name: "Dave"})
      employee_time_entry_fixture(%{employee_id: emp1.id, business_id: biz.id})
      employee_time_entry_fixture(%{employee_id: emp2.id, business_id: biz.id})

      entries = Employees.list_all_time_entries(biz.id)
      assert length(entries) == 2
      assert Enum.all?(entries, fn e -> is_binary(e.employee.name) end)
    end
  end

  describe "get_open_entry/2" do
    test "returns open entry for employee", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})
      open = employee_time_entry_fixture(%{employee_id: emp.id, business_id: biz.id})
      assert Employees.get_open_entry(emp.id, biz.id).id == open.id
    end

    test "returns nil when employee is clocked out", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})

      employee_time_entry_fixture(%{
        employee_id: emp.id,
        business_id: biz.id,
        clocked_in_at: ~N[2026-05-11 08:00:00],
        clocked_out_at: ~N[2026-05-11 16:00:00]
      })

      assert Employees.get_open_entry(emp.id, biz.id) == nil
    end
  end

  describe "update_time_entry/2 (clock out)" do
    test "sets clocked_out_at on open entry", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})
      entry = employee_time_entry_fixture(%{employee_id: emp.id, business_id: biz.id})

      assert {:ok, updated} =
               Employees.update_time_entry(entry, %{clocked_out_at: ~N[2026-05-11 16:00:00]})

      assert updated.clocked_out_at == ~N[2026-05-11 16:00:00]
    end

    test "records lunch break", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})
      entry = employee_time_entry_fixture(%{employee_id: emp.id, business_id: biz.id})

      assert {:ok, updated} =
               Employees.update_time_entry(entry, %{
                 lunch_start_at: ~N[2026-05-11 12:00:00],
                 lunch_end_at: ~N[2026-05-11 13:00:00]
               })

      assert updated.lunch_start_at == ~N[2026-05-11 12:00:00]
      assert updated.lunch_end_at == ~N[2026-05-11 13:00:00]
    end
  end

  describe "total_minutes/2" do
    test "sums worked minutes excluding lunch", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})

      employee_time_entry_fixture(%{
        employee_id: emp.id,
        business_id: biz.id,
        clocked_in_at: ~N[2026-05-11 08:00:00],
        clocked_out_at: ~N[2026-05-11 16:00:00],
        lunch_start_at: ~N[2026-05-11 12:00:00],
        lunch_end_at: ~N[2026-05-11 13:00:00]
      })

      # 8 hours minus 1 hour lunch = 7 hours = 420 minutes
      assert Employees.total_minutes(emp.id, biz.id) == 420
    end

    test "ignores open entries", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})
      employee_time_entry_fixture(%{employee_id: emp.id, business_id: biz.id})
      assert Employees.total_minutes(emp.id, biz.id) == 0
    end
  end

  describe "snapshot_for_sms_ai/1" do
    test "returns employees with open entry info", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id, name: "Henry"})

      employee_time_entry_fixture(%{
        employee_id: emp.id,
        business_id: biz.id,
        clocked_in_at: ~N[2026-05-11 08:00:00]
      })

      [row] = Employees.snapshot_for_sms_ai(biz.id)
      assert row["id"] == emp.id
      assert row["name"] == "Henry"
      assert row["open_entry"]["clocked_in_at"] == "2026-05-11T08:00:00"
    end

    test "open_entry is nil when employee is clocked out", %{biz: biz} do
      emp = employee_fixture(%{business_id: biz.id})

      employee_time_entry_fixture(%{
        employee_id: emp.id,
        business_id: biz.id,
        clocked_in_at: ~N[2026-05-11 08:00:00],
        clocked_out_at: ~N[2026-05-11 16:00:00]
      })

      [row] = Employees.snapshot_for_sms_ai(biz.id)
      assert row["open_entry"] == nil
    end

    test "returns employee with no entries and null open_entry", %{biz: biz} do
      employee_fixture(%{business_id: biz.id, name: "Henry"})
      [row] = Employees.snapshot_for_sms_ai(biz.id)
      assert row["open_entry"] == nil
    end
  end
end
