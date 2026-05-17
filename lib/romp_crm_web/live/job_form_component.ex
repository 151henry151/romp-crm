defmodule RompCrmWeb.JobFormComponent do
  use RompCrmWeb, :live_component

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.BusinessAuditLogs.Detail
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobWorkItem

  @impl true
  def update(%{job: job} = assigns, socket) do
    action = Map.get(assigns, :action)
    job = ensure_default_work_items(job, action)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:current_business_id, fn -> nil end)
     |> assign_new(:actor_user_id, fn -> nil end)
     |> assign_new(:can_edit_jobs, fn -> true end)
     |> assign_new(:form, fn -> to_form(Jobs.change_job(job)) end)}
  end

  defp ensure_default_work_items(%Job{id: nil} = job, :new) do
    case job.work_items do
      list when is_list(list) and list != [] -> job
      _ -> %{job | work_items: [%JobWorkItem{title: "", sort_order: 0}]}
    end
  end

  defp ensure_default_work_items(%Job{id: id} = job, _) when is_integer(id) do
    case job.work_items do
      [] -> %{job | work_items: [%JobWorkItem{title: "", sort_order: 0}]}
      _ -> job
    end
  end

  defp ensure_default_work_items(job, _), do: job

  @impl true
  def handle_event("validate", %{"job" => params} = outer, socket) do
    if socket.assigns.can_edit_jobs do
      params = filter_job_params(params)
      changeset = Jobs.change_job(socket.assigns.job, params)
      {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    else
      _ = outer
      {:noreply, socket}
    end
  end

  def handle_event("save", %{"job" => params} = outer, socket) do
    if not socket.assigns.can_edit_jobs do
      _ = outer
      {:noreply, socket}
    else
      material_lines = Map.get(outer, "material_lines", "") |> to_string()
      params = filter_job_params(params)

      case socket.assigns.action do
        :new -> create_job(socket, params, material_lines)
        :edit -> update_job(socket, params, material_lines)
      end
    end
  end

  def handle_event("add_work_item", _, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, socket}
    else
      job = socket.assigns.job
      next = length(job.work_items || []) + 1

      extra =
        case job.id do
          id when is_integer(id) -> %JobWorkItem{job_id: id, title: "", sort_order: next}
          _ -> %JobWorkItem{title: "", sort_order: next}
        end

      job = %{job | work_items: (job.work_items || []) ++ [extra]}
      cs = Jobs.change_job(job, %{})
      {:noreply, assign(socket, :job, job) |> assign(:form, to_form(cs, action: :validate))}
    end
  end

  defp filter_job_params(params) when is_map(params) do
    case Map.get(params, "work_items") do
      wis when is_list(wis) ->
        kept =
          wis
          |> Enum.map(fn row ->
            row
            |> Enum.map(fn {k, v} -> {to_string(k), v} end)
            |> Map.new()
          end)
          |> Enum.filter(fn row -> (row["title"] || "") |> to_string() |> String.trim() != "" end)
          |> Enum.with_index()
          |> Enum.map(fn {row, i} -> Map.put(row, "sort_order", i) end)

        Map.put(params, "work_items", kept)

      _ ->
        params
    end
  end

  defp material_lines_to_list(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp create_job(socket, params, material_lines) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.actor_user_id

    params =
      params
      |> Map.delete("materials")
      |> Map.put("business_id", to_string(bid))

    case Jobs.create_job(params) do
      {:ok, job} ->
        :ok = Jobs.sync_root_materials_only(job, material_lines_to_list(material_lines))
        job = Jobs.get_job!(job.id, bid)
        lines = material_lines_to_list(material_lines)

        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "jobs.create",
          entity_type: "jobs",
          entity_id: job.id,
          metadata: %{
            client_name: job.client_name,
            job_id: job.id,
            changes:
              Detail.changes_for_job_created(job) ++
                if(lines == [],
                  do: [],
                  else: [
                    %{
                      type: "root_materials_replaced",
                      job_id: job.id,
                      client_name: job.client_name,
                      lines: lines
                    }
                  ]
                )
          }
        })

        notify_parent({:saved, job})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_job(socket, params, material_lines) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.actor_user_id
    job = socket.assigns.job

    params = Map.delete(params, "materials")

    case Jobs.update_job(job, params) do
      {:ok, job} ->
        :ok = Jobs.sync_root_materials_only(job, material_lines_to_list(material_lines))

        lines = material_lines_to_list(material_lines)

        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "jobs.update",
          entity_type: "jobs",
          entity_id: job.id,
          metadata: %{
            client_name: job.client_name,
            job_id: job.id,
            changes:
              if(lines == [],
                do: [],
                else: [
                  %{
                    type: "root_materials_replaced",
                    job_id: job.id,
                    client_name: job.client_name,
                    lines: lines
                  }
                ]
              )
          }
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
    job = assigns.job
    photo_action = if job.id, do: ~p"/jobs/#{job.id}/photos", else: nil

    work_item_options =
      if job.id do
        items =
          (job.work_items || [])
          |> Enum.filter(fn wi -> wi.id && String.trim(to_string(wi.title || "")) != "" end)
          |> Enum.map(fn wi ->
            {String.slice(to_string(wi.title), 0, 44) <> " (#{wi.id})", to_string(wi.id)}
          end)

        [{"— Whole job —", ""}] ++ items
      else
        [{"— Whole job —", ""}]
      end

    assigns =
      assigns
      |> assign(:photo_action, photo_action)
      |> assign(:work_item_photo_options, work_item_options)

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

        <.input field={@form[:scheduled_on]} type="date" label="Job scheduled date (optional)" />

        <.input field={@form[:work_description]} type="textarea" label="Work summary (optional)" rows="2" />

        <div class="rounded-lg border border-base-300 bg-base-200/30 p-3 space-y-3">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-base-content">Work items / tasks</span>
            <button
              :if={@can_edit_jobs}
              type="button"
              phx-click="add_work_item"
              phx-target={@myself}
              class="btn btn-ghost btn-xs"
            >
              + Add line
            </button>
          </div>
          <.inputs_for :let={wi} field={@form[:work_items]}>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 border-b border-base-300/80 pb-2 last:border-0">
              <.input field={wi[:title]} type="text" label="Task description" />
              <.input field={wi[:scheduled_on]} type="date" label="Scheduled (optional)" />
              <.input field={wi[:completed]} type="checkbox" label="Completed" />
            </div>
          </.inputs_for>
        <p class="text-xs text-base-content/60">
          One row per task. SMS can add lines too.
        </p>
        </div>

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

        <div>
          <label for="job-material-lines" class="block text-sm font-medium mb-1">
            Materials (whole job) — one per line
          </label>
          <textarea
            id="job-material-lines"
            name="material_lines"
            rows="3"
            class="textarea textarea-bordered w-full text-sm"
            placeholder="e.g. Copper elbow&#10;Teflon tape"
          ><%= material_lines_value(@job) %></textarea>
          <p class="text-xs text-base-content/60 mt-1">
            Per-task materials: add via SMS; they appear in the list below.
          </p>
        </div>

        <div class="flex justify-end pt-2">
          <%= if @can_edit_jobs do %>
            <.button type="submit" phx-disable-with="Saving…">Save Job</.button>
          <% else %>
            <p class="text-sm text-base-content/70">You do not have permission to save job changes.</p>
          <% end %>
        </div>
      </.form>

      <%= if @photo_action && @can_edit_jobs do %>
        <div class="rounded-lg border border-dashed border-base-300 p-3 space-y-2 mt-4">
          <p class="text-sm font-medium text-base-content">Upload photo</p>
          <form action={@photo_action} method="post" enctype="multipart/form-data" class="flex flex-wrap items-end gap-2">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <div>
              <label class="text-xs text-base-content/70 block mb-0.5">Attach to</label>
              <select name="job_work_item_id" class="select select-bordered select-sm">
                <%= for {label, val} <- @work_item_photo_options do %>
                  <option value={val}>{label}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-xs text-base-content/70 block mb-0.5">File</label>
              <input
                type="file"
                name="photo"
                accept="image/*"
                class="file-input file-input-bordered file-input-sm w-full max-w-xs"
                required
              />
            </div>
            <button type="submit" class="btn btn-outline btn-sm">Upload</button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  defp material_lines_value(%Job{id: nil}), do: ""

  defp material_lines_value(%Job{} = job) do
    (job.materials || [])
    |> Enum.filter(&is_nil(&1.job_work_item_id))
    |> Enum.sort_by(&{&1.sort_order, &1.id})
    |> Enum.map_join("\n", & &1.description)
  end
end
