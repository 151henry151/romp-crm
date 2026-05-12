defmodule RompCrmWeb.EmployeesLive do
  use RompCrmWeb, :live_view

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses
  alias RompCrm.Employees
  alias RompCrm.Employees.Employee

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket), do: Employees.subscribe(bid)

    {:ok,
     socket
     |> assign(:employees, Employees.list_employees(bid))
     |> assign(:employee, nil)
     |> assign(:is_business_owner, Businesses.owner?(socket.assigns.current_scope.user, bid))}
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

  defp display_cell(nil), do: "—"
  defp display_cell(""), do: "—"

  defp display_cell(v) when is_binary(v) do
    if String.trim(v) == "", do: "—", else: v
  end

  defp display_cell(v), do: v

  @impl true
  def handle_event("invite_to_app", %{"id" => id}, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user
    emp = Employees.get_employee!(String.to_integer(id), bid)
    norm = emp.email |> to_string() |> String.trim()

    cond do
      norm == "" ->
        {:noreply, put_flash(socket, :error, "Add an email to this employee before inviting them.")}

      emp.user_id != nil ->
        {:noreply, put_flash(socket, :info, "That employee already has an app account linked.")}

      true ->
        biz = Businesses.get_business!(bid)

        case Businesses.invite_user(biz, user, norm) do
          {:ok, _} ->
            {:noreply, socket |> refresh() |> put_flash(:info, "Invitation sent to #{norm}.")}

          {:error, :not_owner} ->
            {:noreply, put_flash(socket, :error, "Not allowed.")}

          {:error, :already_member} ->
            {:noreply, put_flash(socket, :info, "That email is already a member of this business.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :error, "Could not send invitation (duplicate invite?).")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user
    emp = Employees.get_employee!(String.to_integer(id), bid)

    case Employees.delete_employee(emp) do
      {:ok, _} ->
        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: user.id,
          source: "web",
          action: "employees.delete",
          entity_type: "employees",
          entity_id: emp.id,
          metadata: %{name: emp.name}
        })

        {:noreply, refresh(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete that employee.")}
    end
  end
end
