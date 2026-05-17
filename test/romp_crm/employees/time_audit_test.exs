defmodule RompCrm.Employees.TimeAuditTest do
  use ExUnit.Case, async: true

  alias RompCrm.Employees.EmployeeTimeEntry
  alias RompCrm.Employees.TimeAudit

  test "changes_for_create labels live punch" do
    entry = %EmployeeTimeEntry{
      id: 1,
      employee_id: 2,
      clocked_in_at: ~N[2026-05-17 08:00:00],
      clock_in_kind: :live_punch
    }

    [change] =
      TimeAudit.changes_for_create(entry,
        event: :live_clock_in,
        via: :web,
        employee_name: "Bob"
      )

    assert change.action == "clock_in"
    assert change.record_kind == "live_punch"
    assert change.via == "web"
  end

  test "changes_for_update includes field diffs on adjustment" do
    before = %{
      clocked_in_at: ~N[2026-05-17 08:00:00],
      clocked_out_at: ~N[2026-05-17 16:00:00],
      lunch_start_at: nil,
      lunch_end_at: nil,
      notes: nil
    }

    entry = %EmployeeTimeEntry{
      id: 5,
      employee_id: 2,
      clocked_in_at: ~N[2026-05-17 08:00:00],
      clocked_out_at: ~N[2026-05-17 17:00:00],
      clock_in_kind: :live_punch,
      clock_out_kind: :live_punch
    }

    [change] =
      TimeAudit.changes_for_update(entry,
        event: :manual_adjustment,
        via: :web,
        employee_name: "Bob",
        before: before
      )

    assert change.action == "adjustment"
    assert change.record_kind == "adjustment"

    assert [%{field: "clocked_out_at", before: "2026-05-17T16:00:00", after: "2026-05-17T17:00:00"}] =
             change.field_changes
  end
end
