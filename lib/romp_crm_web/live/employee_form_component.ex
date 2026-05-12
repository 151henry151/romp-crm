defmodule RompCrmWeb.EmployeeFormComponent do
  use RompCrmWeb, :live_component

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Employees

  @impl true
  def update(%{employee: employee} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:current_business_id, fn -> nil end)
     |> assign_new(:actor_user_id, fn -> nil end)
     |> assign_new(:form, fn -> to_form(Employees.change_employee(employee)) end)}
  end

  @impl true
  def handle_event("validate", %{"employee" => params}, socket) do
    changeset = Employees.change_employee(socket.assigns.employee, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"employee" => params}, socket) do
    case socket.assigns.action do
      :new -> create_employee(socket, params)
      :edit -> update_employee(socket, params)
    end
  end

  defp create_employee(socket, params) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.actor_user_id
    params = Map.put(params, "business_id", to_string(bid))

    case Employees.create_employee(params) do
      {:ok, employee} ->
        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "employees.create",
          entity_type: "employees",
          entity_id: employee.id,
          metadata: %{name: employee.name}
        })

        notify_parent({:saved, employee})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_employee(socket, params) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.actor_user_id
    emp = socket.assigns.employee

    case Employees.update_employee(emp, params) do
      {:ok, employee} ->
        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "employees.update",
          entity_type: "employees",
          entity_id: employee.id,
          metadata: %{name: employee.name}
        })

        notify_parent({:saved, employee})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>

      <.form
        for={@form}
        id="employee-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="mt-4 space-y-4"
      >
        <.input field={@form[:name]} type="text" label="Name" required />

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:phone]} type="text" label="Phone" />
          <.input field={@form[:email]} type="text" label="Email" />
        </div>

        <.input field={@form[:title]} type="text" label="Title / Role" />
        <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />

        <div class="rounded-lg border border-base-300 bg-base-200/30 px-4 py-3 space-y-3 text-sm">
          <p class="font-medium text-base-content/90">App permissions (this business)</p>
          <p class="text-xs text-base-content/70">
            Defaults: job time + own employee time on; job edits and logging time for others off.
          </p>
          <.input field={@form[:can_edit_jobs]} type="checkbox" label="Can edit jobs (web & SMS)" />
          <.input field={@form[:can_log_job_time]} type="checkbox" label="Can log time on jobs" />
          <.input
            field={@form[:can_log_own_employee_time]}
            type="checkbox"
            label="Can log their own employee time (clock in/out)"
          />
          <.input
            field={@form[:can_log_employee_time_for_others]}
            type="checkbox"
            label="Can log employee time for other people"
          />
        </div>

        <div class="flex justify-end pt-2">
          <.button type="submit" phx-disable-with="Saving…">Save Employee</.button>
        </div>
      </.form>
    </div>
    """
  end
end
