defmodule RompCrmWeb.JobFormComponent do
  use RompCrmWeb, :live_component

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Jobs

  @impl true
  def update(%{job: job} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:current_business_id, fn -> nil end)
     |> assign_new(:actor_user_id, fn -> nil end)
     |> assign_new(:can_edit_jobs, fn -> true end)
     |> assign_new(:form, fn -> to_form(Jobs.change_job(job)) end)}
  end

  @impl true
  def handle_event("validate", %{"job" => params}, socket) do
    if socket.assigns.can_edit_jobs do
      changeset = Jobs.change_job(socket.assigns.job, params)
      {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", %{"job" => params}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, socket}
    else
      case socket.assigns.action do
        :new -> create_job(socket, params)
        :edit -> update_job(socket, params)
      end
    end
  end

  defp create_job(socket, params) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.actor_user_id

    params =
      params
      |> Map.put("business_id", to_string(bid))

    case Jobs.create_job(params) do
      {:ok, job} ->
        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "jobs.create",
          entity_type: "jobs",
          entity_id: job.id,
          metadata: %{client_name: job.client_name}
        })

        notify_parent({:saved, job})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_job(socket, params) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.actor_user_id
    job = socket.assigns.job

    case Jobs.update_job(job, params) do
      {:ok, job} ->
        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "jobs.update",
          entity_type: "jobs",
          entity_id: job.id,
          metadata: %{client_name: job.client_name}
        })

        notify_parent({:saved, job})
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
        id="job-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="mt-4 space-y-4"
      >
        <.input field={@form[:client_name]} type="text" label="Client Name" required />

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:address]} type="text" label="Address" />
          <.input field={@form[:phone]} type="text" label="Phone" />
        </div>

        <.input field={@form[:work_description]} type="textarea" label="Work Description" rows="3" />

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:priority]}
            type="select"
            label="Priority"
            options={[{"Normal", "normal"}, {"High", "high"}]}
          />
          <.input
            field={@form[:status]}
            type="select"
            label="Status"
            options={[
              {"Lead", "lead"},
              {"Pending", "pending"},
              {"In Progress", "in_progress"},
              {"Done", "done"}
            ]}
          />
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:referred_by]} type="text" label="Referred By" />
          <.input field={@form[:next_action]} type="text" label="Next Action" />
        </div>

        <.input field={@form[:notes]} type="textarea" label="Notes / Availability" rows="3" />

        <div class="flex justify-end pt-2">
          <%= if @can_edit_jobs do %>
            <.button type="submit" phx-disable-with="Saving…">Save Job</.button>
          <% else %>
            <p class="text-sm text-base-content/70">You do not have permission to save job changes.</p>
          <% end %>
        </div>
      </.form>
    </div>
    """
  end
end
