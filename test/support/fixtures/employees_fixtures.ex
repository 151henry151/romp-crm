defmodule RompCrm.EmployeesFixtures do
  @moduledoc "Test helpers for creating employees and employee time entries."

  alias RompCrm.Employees
  alias RompCrm.JobsFixtures

  @doc "Creates an employee with defaults. Pass `:business_id` to reuse existing business."
  def employee_fixture(attrs \\ %{}) do
    {business_id, attrs} =
      case Map.pop(attrs, :business_id) do
        {nil, attrs} -> {JobsFixtures.business_fixture().id, attrs}
        {bid, attrs} -> {bid, attrs}
      end

    final_attrs =
      Enum.into(attrs, %{
        business_id: business_id,
        name: "Test Employee"
      })

    {:ok, employee} = Employees.create_employee(final_attrs)
    employee
  end

  @doc "Creates an employee time entry. Requires `:employee_id` and `:business_id`."
  def employee_time_entry_fixture(attrs \\ %{}) do
    {employee_id, business_id, attrs} =
      case {Map.pop(attrs, :employee_id), Map.pop(attrs, :business_id)} do
        {{nil, attrs}, {nil, attrs2}} ->
          emp = employee_fixture()
          {emp.id, emp.business_id, Map.merge(attrs, attrs2)}

        {{emp_id, attrs}, {nil, attrs2}} ->
          emp = Employees.get_employee!(emp_id, Map.get(attrs2, :business_id, emp_id))
          {emp_id, emp.business_id, Map.merge(attrs, attrs2)}

        {{nil, attrs}, {bid, attrs2}} ->
          emp = employee_fixture(%{business_id: bid})
          {emp.id, bid, Map.merge(attrs, attrs2)}

        {{emp_id, attrs}, {bid, attrs2}} ->
          {emp_id, bid, Map.merge(attrs, attrs2)}
      end

    final_attrs =
      Enum.into(attrs, %{
        business_id: business_id,
        employee_id: employee_id,
        clocked_in_at: ~N[2026-05-11 08:00:00]
      })

    {:ok, entry} = Employees.create_time_entry(final_attrs)
    entry
  end
end
