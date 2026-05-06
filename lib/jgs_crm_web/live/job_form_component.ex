defmodule JgsCrmWeb.JobFormComponent do
  use JgsCrmWeb, :live_component

  alias JgsCrm.Jobs

  @impl true
  def update(%{job: job} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:current_business_id, fn -> nil end)
     |> assign_new(:form, fn -> to_form(Jobs.change_job(job)) end)}
  end

  @impl true
  def handle_event("validate", %{"job" => params}, socket) do
    changeset = Jobs.change_job(socket.assigns.job, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"job" => params}, socket) do
    case socket.assigns.action do
      :new -> create_job(socket, params)
      :edit -> update_job(socket, params)
    end
  end

  defp create_job(socket, params) do
    bid = socket.assigns.current_business_id

    params =
      params
      |> Map.put("business_id", to_string(bid))

    case Jobs.create_job(params) do
      {:ok, job} ->
        notify_parent({:saved, job})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_job(socket, params) do
    case Jobs.update_job(socket.assigns.job, params) do
      {:ok, job} ->
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
          <.button type="submit" phx-disable-with="Saving…">Save Job</.button>
        </div>
      </.form>
    </div>
    """
  end
end
