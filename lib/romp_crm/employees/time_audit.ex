defmodule RompCrm.Employees.TimeAudit do
  @moduledoc """
  Builds structured audit `changes` for employee workday time entries.
  """

  alias RompCrm.Employees.EmployeeTimeEntry

  @fields ~w(clocked_in_at clocked_out_at lunch_start_at lunch_end_at notes)a

  @doc false
  def snapshot(%EmployeeTimeEntry{} = e) do
    Map.take(e, @fields)
  end

  @doc """
  Audit change list for a newly created entry.

  Options:
    * `:event` — `:live_clock_in`, `:sms_clock_in`, `:manual_shift`, `:sms_shift`
    * `:via` — `:web` | `:sms`
    * `:employee_name` — required string
  """
  def changes_for_create(%EmployeeTimeEntry{} = entry, opts) do
    event = Keyword.fetch!(opts, :event)
    via = Keyword.get(opts, :via, :web)
    name = Keyword.fetch!(opts, :employee_name)

    [
      %{
        type: "employee_time",
        action: create_action(event),
        record_kind: record_kind_label(entry, :in),
        event: Atom.to_string(event),
        via: Atom.to_string(via),
        employee_name: name,
        employee_id: entry.employee_id,
        entry_id: entry.id,
        clocked_in_at: format_dt(entry.clocked_in_at),
        clocked_out_at: format_dt(entry.clocked_out_at),
        lunch_start_at: format_dt(entry.lunch_start_at),
        lunch_end_at: format_dt(entry.lunch_end_at),
        notes: entry.notes
      }
    ]
  end

  @doc """
  Audit change list for an updated entry.

  Options:
    * `:event` — `:live_clock_out`, `:sms_clock_out`, `:lunch`, `:manual_adjustment`, `:sms_adjustment`
    * `:via` — `:web` | `:sms`
    * `:employee_name` — required string
    * `:before` — snapshot map from `snapshot/1` before the update
  """
  def changes_for_update(%EmployeeTimeEntry{} = entry, opts) do
    event = Keyword.fetch!(opts, :event)
    via = Keyword.get(opts, :via, :web)
    name = Keyword.fetch!(opts, :employee_name)
    before = Keyword.fetch!(opts, :before)

    after_snap = snapshot(entry)
    field_changes = field_diffs(before, after_snap)

    base = %{
      type: "employee_time",
      action: update_action(event),
      record_kind: update_record_kind(entry, event),
      event: Atom.to_string(event),
      via: Atom.to_string(via),
      employee_name: name,
      employee_id: entry.employee_id,
      entry_id: entry.id,
      clock_in_kind: kind_label(entry.clock_in_kind),
      clock_out_kind: kind_label(entry.clock_out_kind),
      clocked_in_at: format_dt(entry.clocked_in_at),
      clocked_out_at: format_dt(entry.clocked_out_at),
      lunch_start_at: format_dt(entry.lunch_start_at),
      lunch_end_at: format_dt(entry.lunch_end_at),
      notes: entry.notes,
      field_changes: field_changes
    }

    [base]
  end

  @doc false
  def changes_for_delete(%EmployeeTimeEntry{} = entry, opts) do
    name = Keyword.fetch!(opts, :employee_name)
    via = Keyword.get(opts, :via, :web)

    [
      %{
        type: "employee_time",
        action: "delete",
        record_kind: "removed",
        via: Atom.to_string(via),
        employee_name: name,
        employee_id: entry.employee_id,
        entry_id: entry.id,
        clocked_in_at: format_dt(entry.clocked_in_at),
        clocked_out_at: format_dt(entry.clocked_out_at)
      }
    ]
  end

  defp create_action(:live_clock_in), do: "clock_in"
  defp create_action(:sms_clock_in), do: "clock_in"
  defp create_action(:manual_shift), do: "manual_entry"
  defp create_action(:sms_shift), do: "shift_logged"

  defp update_action(:live_clock_out), do: "clock_out"
  defp update_action(:sms_clock_out), do: "clock_out"
  defp update_action(:lunch), do: "lunch"
  defp update_action(:manual_adjustment), do: "adjustment"
  defp update_action(:sms_adjustment), do: "adjustment"

  defp record_kind_label(%EmployeeTimeEntry{} = e, :in) do
    case e.clock_in_kind do
      :live_punch -> "live_punch"
      :sms_punch -> "sms_punch"
      :manual_entry -> "manual_entry"
      :sms_shift -> "shift_logged"
      _ -> "entry"
    end
  end

  defp update_record_kind(%EmployeeTimeEntry{} = e, event) when event in [:live_clock_out, :sms_clock_out] do
    case e.clock_out_kind || e.clock_in_kind do
      :live_punch -> "live_punch"
      :sms_punch -> "sms_punch"
      :manual_entry -> "manual_entry"
      :sms_shift -> "shift_logged"
      _ -> "punch"
    end
  end

  defp update_record_kind(_e, :lunch), do: "lunch"
  defp update_record_kind(_e, _), do: "adjustment"

  defp kind_label(nil), do: nil
  defp kind_label(k) when is_atom(k), do: Atom.to_string(k)
  defp kind_label(k) when is_binary(k), do: k

  defp field_diffs(before, after_snap) do
    Enum.flat_map(@fields, fn field ->
      b = Map.get(before, field)
      a = Map.get(after_snap, field)

      if b != a do
        [%{field: Atom.to_string(field), before: format_dt(b), after: format_dt(a)}]
      else
        []
      end
    end)
  end

  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_dt(nil), do: nil
  defp format_dt(other), do: other
end
