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

  @doc """
  Returns the employee row linked to **`user_id`** in **`business_id`**, if any.
  """
  def get_employee_by_user_id(user_id, business_id)
      when is_integer(user_id) and is_integer(business_id) do
    Repo.one(
      from e in Employee,
        where: e.user_id == ^user_id and e.business_id == ^business_id,
        limit: 1
    )
  end

  @doc """
  Ensures a roster row exists for an invited email (name derived from the local part).

  Returns **`{:ok, :created, employee}`**, **`{:ok, :existing, employee}`**, **`{:ok, :skipped}`**,
  or **`{:error, changeset}`**.
  """
  def ensure_placeholder_for_invitation(business_id, email, _inviter_user_id \\ nil)
      when is_integer(business_id) and is_binary(email) do
    norm = email |> String.trim() |> String.downcase()

    cond do
      norm == "" ->
        {:ok, :skipped}

      true ->
        existing =
          Repo.one(
            from e in Employee,
              where: e.business_id == ^business_id,
              where: fragment("lower(trim(?)) = ?", e.email, ^norm),
              limit: 1
          )

        if existing do
          {:ok, :existing, existing}
        else
          local =
            norm
            |> String.split("@")
            |> List.first()
            |> to_string()
            |> String.replace(~r/[._]+/, " ")
            |> String.trim()

          name = if local == "", do: norm, else: local

          case create_employee(%{
                 "business_id" => business_id,
                 "name" => name,
                 "email" => norm,
                 "can_edit_jobs" => false,
                 "can_log_job_time" => true,
                 "can_log_own_employee_time" => true,
                 "can_log_employee_time_for_others" => false
               }) do
            {:ok, emp} -> {:ok, :created, emp}
            err -> err
          end
        end
    end
  end

  @doc """
  After a user accepts a business invitation, links **`users`** ↔ **`employees`**
  by matching email or creates a new roster row with defaults.
  """
  def link_user_after_invite_accept(business_id, user) when is_integer(business_id) do
    norm = user.email |> String.trim() |> String.downcase()

    cond do
      norm == "" ->
        {:error, :missing_user_email}

      true ->
        existing =
          Repo.one(
            from e in Employee,
              where: e.business_id == ^business_id,
              where: fragment("lower(trim(?)) = ?", e.email, ^norm),
              limit: 1
          )

        case existing do
          %Employee{user_id: nil} = emp ->
            case update_employee(emp, %{user_id: user.id}) do
              {:ok, updated} ->
                RompCrm.BusinessAuditLogs.record(%{
                  business_id: business_id,
                  actor_user_id: user.id,
                  source: "web",
                  action: "employees.link_user",
                  entity_type: "employees",
                  entity_id: updated.id,
                  metadata: %{}
                })

                {:ok, updated}

              err ->
                err
            end

          %Employee{user_id: uid} = emp when uid == user.id ->
            {:ok, emp}

          %Employee{} ->
            {:error, :employee_email_linked_to_other_user}

          nil ->
            local =
              norm
              |> String.split("@")
              |> List.first()
              |> to_string()
              |> String.replace(~r/[._]+/, " ")
              |> String.trim()

            name = if local == "", do: norm, else: local

            case create_employee(%{
                   "business_id" => business_id,
                   "name" => name,
                   "email" => norm,
                   "user_id" => user.id,
                   "can_edit_jobs" => false,
                   "can_log_job_time" => true,
                   "can_log_own_employee_time" => true,
                   "can_log_employee_time_for_others" => false
                 }) do
              {:ok, emp} ->
                RompCrm.BusinessAuditLogs.record(%{
                  business_id: business_id,
                  actor_user_id: user.id,
                  source: "web",
                  action: "employees.create",
                  entity_type: "employees",
                  entity_id: emp.id,
                  metadata: %{reason: "invite_accept_new_roster"}
                })

                {:ok, emp}

              err ->
                err
            end
        end
    end
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
