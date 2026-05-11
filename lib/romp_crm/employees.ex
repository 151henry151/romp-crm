defmodule RompCrm.Employees do
  import Ecto.Query
  alias RompCrm.Repo
  alias RompCrm.Employees.Employee
  alias RompCrm.Employees.EmployeeTimeEntry

  def subscribe(business_id) when is_integer(business_id) do
    Phoenix.PubSub.subscribe(RompCrm.PubSub, topic(business_id))
  end

  defp topic(business_id), do: "employees:business:#{business_id}"

  def list_employees(business_id) when is_integer(business_id) do
    Repo.all(
      from e in Employee,
        where: e.business_id == ^business_id,
        order_by: [asc: e.name]
    )
  end

  def get_employee!(id, business_id) when is_integer(business_id) do
    Repo.get_by!(Employee, id: id, business_id: business_id)
  end

  def get_employee(id, business_id) when is_integer(business_id) do
    Repo.get_by(Employee, id: id, business_id: business_id)
  end

  def create_employee(attrs) do
    with {:ok, employee} <- %Employee{} |> Employee.changeset(attrs) |> Repo.insert() do
      broadcast(employee.business_id, {:employee_created, employee})
      {:ok, employee}
    end
  end

  def update_employee(%Employee{} = employee, attrs) do
    with {:ok, employee} <- employee |> Employee.changeset(attrs) |> Repo.update() do
      broadcast(employee.business_id, {:employee_updated, employee})
      {:ok, employee}
    end
  end

  def delete_employee(%Employee{} = employee) do
    bid = employee.business_id

    with {:ok, employee} <- Repo.delete(employee) do
      broadcast(bid, {:employee_deleted, employee})
      {:ok, employee}
    end
  end

  def change_employee(%Employee{} = employee, attrs \\ %{}) do
    Employee.changeset(employee, attrs)
  end

  # ── Time entry functions ──────────────────────────────────────────────────

  @doc "Time entries for a specific employee, newest first."
  def list_time_entries(employee_id, business_id) when is_integer(business_id) do
    Repo.all(
      from te in EmployeeTimeEntry,
        where: te.employee_id == ^employee_id and te.business_id == ^business_id,
        order_by: [desc: te.clocked_in_at]
    )
  end

  @doc "All employee time entries for a business, newest first, with employee preloaded."
  def list_all_time_entries(business_id) when is_integer(business_id) do
    Repo.all(
      from te in EmployeeTimeEntry,
        where: te.business_id == ^business_id,
        order_by: [desc: te.clocked_in_at],
        preload: [:employee]
    )
  end

  @doc "Returns the open (not clocked out) entry for an employee, or nil."
  def get_open_entry(employee_id, business_id) when is_integer(business_id) do
    Repo.one(
      from te in EmployeeTimeEntry,
        where:
          te.employee_id == ^employee_id and te.business_id == ^business_id and
            is_nil(te.clocked_out_at),
        limit: 1
    )
  end

  def get_time_entry!(id, business_id) when is_integer(business_id) do
    Repo.get_by!(EmployeeTimeEntry, id: id, business_id: business_id)
  end

  def create_time_entry(attrs) do
    with {:ok, entry} <-
           %EmployeeTimeEntry{} |> EmployeeTimeEntry.changeset(attrs) |> Repo.insert() do
      broadcast(entry.business_id, {:employee_time_entry_created, entry})
      {:ok, entry}
    end
  end

  def update_time_entry(%EmployeeTimeEntry{} = entry, attrs) do
    with {:ok, entry} <- entry |> EmployeeTimeEntry.changeset(attrs) |> Repo.update() do
      broadcast(entry.business_id, {:employee_time_entry_updated, entry})
      {:ok, entry}
    end
  end

  def delete_time_entry(%EmployeeTimeEntry{} = entry) do
    bid = entry.business_id

    with {:ok, entry} <- Repo.delete(entry) do
      broadcast(bid, {:employee_time_entry_deleted, entry})
      {:ok, entry}
    end
  end

  def change_time_entry(%EmployeeTimeEntry{} = entry, attrs \\ %{}) do
    EmployeeTimeEntry.changeset(entry, attrs)
  end

  @doc "Sum of completed entry worked minutes for an employee."
  def total_minutes(employee_id, business_id) when is_integer(business_id) do
    list_time_entries(employee_id, business_id)
    |> Enum.reduce(0, fn entry, acc ->
      case EmployeeTimeEntry.worked_minutes(entry) do
        nil -> acc
        mins -> acc + mins
      end
    end)
  end

  @doc """
  Returns employees with their open clock-in entry for SMS AI context.
  """
  def snapshot_for_sms_ai(business_id) when is_integer(business_id) do
    employees = list_employees(business_id)

    open_entries =
      Repo.all(
        from te in EmployeeTimeEntry,
          where: te.business_id == ^business_id and is_nil(te.clocked_out_at)
      )

    open_by_emp = Map.new(open_entries, fn te -> {te.employee_id, te} end)

    Enum.map(employees, fn emp ->
      open = Map.get(open_by_emp, emp.id)

      %{
        "id" => emp.id,
        "name" => emp.name,
        "phone" => emp.phone,
        "title" => emp.title,
        "open_entry" =>
          if open do
            %{
              "entry_id" => open.id,
              "clocked_in_at" => NaiveDateTime.to_iso8601(open.clocked_in_at),
              "lunch_start_at" =>
                open.lunch_start_at && NaiveDateTime.to_iso8601(open.lunch_start_at),
              "lunch_end_at" => open.lunch_end_at && NaiveDateTime.to_iso8601(open.lunch_end_at)
            }
          else
            nil
          end
      }
    end)
  end

  defp broadcast(business_id, message) do
    Phoenix.PubSub.broadcast(RompCrm.PubSub, topic(business_id), message)
  end
end
