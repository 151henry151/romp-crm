defmodule RompCrmWeb.EmployeesLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Employees
  alias RompCrm.Employees.Employee

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket), do: Employees.subscribe(bid)

    {:ok,
     socket
     |> assign(:employees, Employees.list_employees(bid))
     |> assign(:employee, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :employee, nil)
  end

  defp apply_action(socket, :new, _params) do
    bid = socket.assigns.current_business_id
    assign(socket, :employee, %Employee{business_id: bid})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    bid = socket.assigns.current_business_id
    assign(socket, :employee, Employees.get_employee!(String.to_integer(id), bid))
  end

  @impl true
  def handle_info({:employee_created, _emp}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:employee_updated, _emp}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:employee_deleted, _emp}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({RompCrmWeb.EmployeeFormComponent, {:saved, _emp}}, socket) do
    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    assign(socket, :employees, Employees.list_employees(socket.assigns.current_business_id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    bid = socket.assigns.current_business_id
    emp = Employees.get_employee!(String.to_integer(id), bid)
    {:ok, _} = Employees.delete_employee(emp)
    {:noreply, refresh(socket)}
  end
end
