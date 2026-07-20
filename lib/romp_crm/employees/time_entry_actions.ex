defmodule RompCrm.Employees.TimeEntryActions do
  @moduledoc """
  Shared create/update/delete for employee workday time entries with audit logging.
  """

  alias RompCrm.Accounts.User
  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Employees
  alias RompCrm.Employees.{EmployeeTimeEntry, TimeAudit}
  alias RompCrm.LocalWallClock
  alias RompCrm.Reminders
  alias RompCrm.Repo

  @doc "Live punch in from the workday timeclock UI."
  def clock_in_live(business_id, actor_user_id, employee, at \\ nil) do
    at = at || default_live_punch_at(actor_user_id)

    attrs = %{
      business_id: business_id,
      employee_id: employee.id,
      clocked_in_at: at,
      clock_in_kind: :live_punch
    }

    with {:ok, entry} <- Employees.create_time_entry(attrs) do
      record_audit(business_id, actor_user_id, "web", "employee_time_entries.create", entry, %{
        changes: TimeAudit.changes_for_create(entry, event: :live_clock_in, via: :web, employee_name: employee.name)
      })

      {:ok, entry}
    end
  end

  @doc "Live punch out from the workday timeclock UI."
  def clock_out_live(business_id, actor_user_id, employee, %EmployeeTimeEntry{} = entry, at \\ nil) do
    at = at || default_live_punch_at(actor_user_id)
    before = TimeAudit.snapshot(entry)

    attrs = %{clocked_out_at: at, clock_out_kind: :live_punch}

    with {:ok, updated} <- Employees.update_time_entry(entry, attrs) do
      record_audit(business_id, actor_user_id, "web", "employee_time_entries.update", updated, %{
        changes:
          TimeAudit.changes_for_update(updated,
            event: :live_clock_out,
            via: :web,
            employee_name: employee.name,
            before: before
          )
      })

      {:ok, updated}
    end
  end

  @doc "Create a completed shift (manual form or SMS log_shift)."
  def create_shift(business_id, actor_user_id, employee, attrs, opts) do
    via = Keyword.get(opts, :via, :web)
    audit_extra = Keyword.get(opts, :audit_extra, %{})
    in_kind = Keyword.get(opts, :clock_in_kind, :manual_entry)
    out_kind = Keyword.get(opts, :clock_out_kind, in_kind)

    attrs =
      attrs
      |> Map.put(:business_id, business_id)
      |> Map.put(:employee_id, employee.id)
      |> Map.put(:clock_in_kind, in_kind)
      |> Map.put(:clock_out_kind, out_kind)

    event =
      case in_kind do
        :sms_shift -> :sms_shift
        _ -> :manual_shift
      end

    with {:ok, entry} <- Employees.create_time_entry(attrs) do
      record_audit(
        business_id,
        actor_user_id,
        Atom.to_string(via),
        "employee_time_entries.create",
        entry,
        %{changes: TimeAudit.changes_for_create(entry, event: event, via: via, employee_name: employee.name)},
        audit_extra
      )

      {:ok, entry}
    end
  end

  @doc "Adjust times on an existing entry (web or SMS)."
  def adjust_entry(business_id, actor_user_id, employee, %EmployeeTimeEntry{} = entry, attrs, opts) do
    via = Keyword.get(opts, :via, :web)
    audit_extra = Keyword.get(opts, :audit_extra, %{})
    event = if(via == :sms, do: :sms_adjustment, else: :manual_adjustment)
    before = TimeAudit.snapshot(entry)

    with {:ok, updated} <- Employees.update_time_entry(entry, attrs) do
      record_audit(
        business_id,
        actor_user_id,
        Atom.to_string(via),
        "employee_time_entries.update",
        updated,
        %{
          changes:
            TimeAudit.changes_for_update(updated,
              event: event,
              via: via,
              employee_name: employee.name,
              before: before
            )
        },
        audit_extra
      )

      {:ok, updated}
    end
  end

  @doc "Delete an entry with audit."
  def delete_entry(business_id, actor_user_id, employee, %EmployeeTimeEntry{} = entry, opts \\ []) do
    via = Keyword.get(opts, :via, :web)

    with {:ok, deleted} <- Employees.delete_time_entry(entry) do
      record_audit(business_id, actor_user_id, Atom.to_string(via), "employee_time_entries.delete", deleted, %{
        changes: TimeAudit.changes_for_delete(deleted, via: via, employee_name: employee.name)
      })

      {:ok, deleted}
    end
  end

  @doc "SMS clock-in with explicit time."
  def sms_clock_in(business_id, actor_user_id, employee, clocked_in_at, opts \\ []) do
    audit_extra = Keyword.get(opts, :audit_extra, %{})
    case Employees.get_open_entry(employee.id, business_id) do
      %EmployeeTimeEntry{} = open ->
        {:error, :already_clocked_in, open}

      nil ->
        attrs = %{
          business_id: business_id,
          employee_id: employee.id,
          clocked_in_at: clocked_in_at,
          clock_in_kind: :sms_punch
        }

        with {:ok, entry} <- Employees.create_time_entry(attrs) do
          record_audit(
            business_id,
            actor_user_id,
            "sms",
            "employee_time_entries.create",
            entry,
            %{changes: TimeAudit.changes_for_create(entry, event: :sms_clock_in, via: :sms, employee_name: employee.name)},
            audit_extra
          )

          {:ok, entry}
        end
    end
  end

  @doc "SMS clock-out on the open entry."
  def sms_clock_out(business_id, actor_user_id, employee, clocked_out_at, opts \\ []) do
    audit_extra = Keyword.get(opts, :audit_extra, %{})
    case Employees.get_open_entry(employee.id, business_id) do
      nil ->
        {:error, :no_open_entry}

      entry ->
        before = TimeAudit.snapshot(entry)

        with {:ok, updated} <-
               Employees.update_time_entry(entry, %{clocked_out_at: clocked_out_at, clock_out_kind: :sms_punch}) do
          record_audit(
            business_id,
            actor_user_id,
            "sms",
            "employee_time_entries.update",
            updated,
            %{
              changes:
                TimeAudit.changes_for_update(updated,
                  event: :sms_clock_out,
                  via: :sms,
                  employee_name: employee.name,
                  before: before
                )
            },
            audit_extra
          )

          {:ok, updated}
        end
    end
  end

  @doc "SMS lunch on the open entry."
  def sms_lunch(business_id, actor_user_id, employee, lunch_start, lunch_end, opts \\ []) do
    audit_extra = Keyword.get(opts, :audit_extra, %{})
    case Employees.get_open_entry(employee.id, business_id) do
      nil ->
        {:error, :no_open_entry}

      entry ->
        before = TimeAudit.snapshot(entry)

        with {:ok, updated} <-
               Employees.update_time_entry(entry, %{lunch_start_at: lunch_start, lunch_end_at: lunch_end}) do
          record_audit(
            business_id,
            actor_user_id,
            "sms",
            "employee_time_entries.update",
            updated,
            %{
              changes:
                TimeAudit.changes_for_update(updated,
                  event: :lunch,
                  via: :sms,
                  employee_name: employee.name,
                  before: before
                )
            },
            audit_extra
          )

          {:ok, updated}
        end
    end
  end

  defp default_live_punch_at(actor_user_id) when is_integer(actor_user_id) do
    tz =
      case Repo.get(User, actor_user_id) do
        %User{} = user ->
          user.sms_reminder_prefs_json
          |> Reminders.decode_prefs_json()
          |> Map.get("timezone", LocalWallClock.default_timezone())

        _ ->
          LocalWallClock.default_timezone()
      end

    LocalWallClock.now(tz)
  end

  defp default_live_punch_at(_), do: LocalWallClock.now()

  defp record_audit(business_id, actor_user_id, source, action, entry, metadata, audit_extra \\ %{}) do
    metadata =
      metadata
      |> Map.put(:employee_id, entry.employee_id)
      |> Map.merge(audit_extra)

    BusinessAuditLogs.record(%{
      business_id: business_id,
      actor_user_id: actor_user_id,
      source: source,
      action: action,
      entity_type: "employee_time_entries",
      entity_id: entry.id,
      metadata: metadata
    })
  end
end

