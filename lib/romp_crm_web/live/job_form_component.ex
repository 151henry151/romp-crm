defmodule RompCrmWeb.JobFormComponent do
  use RompCrmWeb, :live_component

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Clients
  alias RompCrm.Clients.ClientContact
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobWorkItem
  alias RompCrmWeb.AddressFormHandlers
  alias RompCrmWeb.AddressValues
  alias RompCrm.ContactInfo

  @impl true
  def update(%{job: incoming_job} = assigns, socket) do
    action = Map.get(assigns, :action)
    incoming_job = ensure_default_work_items(incoming_job, action)
    job = preserve_local_work_items(socket, incoming_job)

    form = to_form(Jobs.change_job(job))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:job, job)
     |> assign_new(:current_business_id, fn -> nil end)
     |> assign_new(:actor_user_id, fn -> nil end)
     |> assign_new(:can_edit_jobs, fn -> true end)
     |> assign_new(:address_suggestion, fn -> nil end)
     |> assign_new(:clients_for_picker, fn -> [] end)
     |> assign(:form, form)}
  end

  defp preserve_local_work_items(socket, incoming_job) do
    case socket.assigns[:job] do
      %Job{id: id} = current when id == incoming_job.id or is_nil(id) and is_nil(incoming_job.id) ->
        current_items = current.work_items || []
        incoming_items = incoming_job.work_items || []

        if length(current_items) > length(incoming_items) do
          %{incoming_job | work_items: current_items}
        else
          incoming_job
        end

      _ ->
        incoming_job
    end
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
      params = normalize_job_params(params)
      job = merge_client_pick(socket, params)
      changeset = Jobs.change_job(job, params)
      {:noreply, assign(socket, :job, job) |> assign(:form, to_form(changeset, action: :validate))}
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

  def handle_event("address_validate", params, socket) do
    suggestion = AddressFormHandlers.build_suggestion(params)
    {:noreply, assign(socket, :address_suggestion, suggestion)}
  end

  def handle_event("address_apply_choice", %{"choice" => choice, "part" => part}, socket) do
    suggestion = socket.assigns[:address_suggestion]

    if suggestion && suggestion["part"] == part do
      fill =
        if choice == "suggested" do
          suggestion["suggested"]
        else
          suggestion["typed"]
        end

      params =
        socket.assigns.form.params
        |> case do
          p when is_map(p) -> %{"job" => p}
          _ -> %{"job" => %{}}
        end
        |> AddressFormHandlers.merge_fill_into_job_params(fill, part)

      job_params = Map.get(params, "job", %{})
      changeset = Jobs.change_job(socket.assigns.job, job_params)

      {:noreply,
       socket
       |> assign(:address_suggestion, nil)
       |> assign(:form, to_form(changeset, action: :validate))
       |> push_event("address_fill", %{part: part, fields: fill})}
    else
      {:noreply, socket}
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
    params
    |> normalize_job_params()
    |> drop_blank_work_items()
  end

  defp normalize_job_params(params) when is_map(params) do
    params
    |> normalize_work_items_param()
    |> then(fn p ->
      case Map.get(p, "work_items") do
        wis when is_list(wis) ->
          kept =
            wis
            |> Enum.map(fn row ->
              row
              |> Enum.map(fn {k, v} -> {to_string(k), v} end)
              |> Map.new()
            end)
            |> Enum.with_index()
            |> Enum.map(fn {row, i} -> Map.put(row, "sort_order", i) end)

          Map.put(p, "work_items", kept)

        _ ->
          p
      end
    end)
  end

  defp normalize_work_items_param(%{"work_items" => wis} = params) when is_map(wis) do
    list =
      wis
      |> Enum.sort_by(fn {key, _} -> work_items_param_sort_key(key) end)
      |> Enum.map(fn {_, row} -> row end)

    Map.put(params, "work_items", list)
  end

  defp normalize_work_items_param(params), do: params

  defp work_items_param_sort_key(key) when is_binary(key) do
    case Integer.parse(key) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp work_items_param_sort_key(key) when is_integer(key), do: key
  defp work_items_param_sort_key(_), do: 0

  defp drop_blank_work_items(%{"work_items" => wis} = params) when is_list(wis) do
    kept =
      wis
      |> Enum.filter(fn row -> (row["title"] || "") |> to_string() |> String.trim() != "" end)
      |> Enum.with_index()
      |> Enum.map(fn {row, i} -> Map.put(row, "sort_order", i) end)

    Map.put(params, "work_items", kept)
  end

  defp drop_blank_work_items(params), do: params

  defp material_lines_to_list(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp create_job(socket, params, material_lines) do
    notify_parent({:job_save_requested, params, material_lines})
    {:noreply, socket}
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

  defp merge_client_pick(socket, %{"client_id" => id}) when id not in [nil, ""] do
    bid = socket.assigns.current_business_id

    case Integer.parse(to_string(id)) do
      {client_id, _} ->
        case Clients.get_client(client_id, bid) do
          nil ->
            socket.assigns.job

          client ->
            contact = ClientContact.from_struct(client)

            socket.assigns.job
            |> struct(contact)
            |> Map.put(:client_id, client.id)
            |> Map.put(:client, client)
        end

      :error ->
        socket.assigns.job
    end
  end

  defp merge_client_pick(socket, _), do: socket.assigns.job

  defp client_picker_options(clients) do
    base = [{"— Type contact or pick existing client —", ""}]

    Enum.reduce(clients, base, fn client, acc ->
      label =
        [client.client_name, client.phone]
        |> Enum.map(&(&1 |> to_string() |> String.trim()))
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" · ")

      label = if label == "", do: "Client ##{client.id}", else: label
      [{label, to_string(client.id)} | acc]
    end)
    |> Enum.reverse()
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
      |> assign(:client_picker_options, client_picker_options(assigns.clients_for_picker))

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
        <%= if @action == :new do %>
          <.input
            field={@form[:client_id]}
            type="select"
            label="Existing client (optional)"
            options={@client_picker_options}
          />
        <% end %>

        <.input field={@form[:client_name]} type="text" label="Client Name" />
        <p class="text-xs text-base-content/60 -mt-2">
          Client name, address, work summary, phone, or notes — at least one is required.
        </p>

        <.address_fields
          id="job-form-address"
          name_prefix="job"
          target={@myself}
          values={AddressValues.from_form(@form, @job)}
          suggestion={@address_suggestion}
        />

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.phone_field
          id="job-form-phone"
          name={@form[:phone].name}
          value={@form[:phone].value}
          label="Phone"
          errors={@form[:phone].errors}
        />

        <.input
          field={@form[:client_email]}
          type="email"
          label="Email"
          pattern={ContactInfo.email_html_pattern()}
          title={ContactInfo.email_hint()}
        />
        </div>

        <.input field={@form[:scheduled_on]} type="date" label="Job scheduled date (optional)" />

        <.input field={@form[:work_description]} type="textarea" label="Work summary (optional)" rows="2" />
        <.input field={@form[:customer_comments]} type="textarea" label="Customer comments (optional)" rows="2" />

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
              <.input field={wi[:scheduled_on]} type="date" label="Scheduled" />
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
