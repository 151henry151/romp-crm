defmodule RompCrmWeb.JobsLive do
  use RompCrmWeb, :live_view

  import RompCrmWeb.JobExpandLists
  import RompCrmWeb.JobExpandedInlineFields

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.TimeTracking
  alias RompCrm.TimeTracking.TimeEntry
  alias RompCrm.Twilio.Phone
  alias RompCrmWeb.DatetimeLocal
  alias RompCrmWeb.JobTimeLogDefaults

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket) do
      Jobs.subscribe(bid)
      TimeTracking.subscribe(bid)
    end

    sms_from =
      case Application.get_env(:romp_crm, :twilio_messaging_from_number) do
        s when is_binary(s) ->
          case String.trim(s) do
            "" -> "+18022780965"
            t -> t
          end

        _ ->
          "+18022780965"
      end

    user = socket.assigns.current_scope.user
    caps = EmployeePermissions.for(user, bid)

    {:ok,
     socket
     |> assign(:filter, :all)
     |> assign(:expanded_job_id, nil)
     |> assign(:expanded_time_entries, %{})
     |> assign(:jobs, Jobs.list_jobs(bid))
     |> assign(:can_edit_jobs, EmployeePermissions.can_edit_jobs?(caps))
     |> assign(:can_log_job_time, EmployeePermissions.can_log_job_time?(caps))
     |> assign(:is_business_owner, Businesses.owner?(user, bid))
     |> assign(:can_punch_own_timeclock, EmployeePermissions.can_punch_own_timeclock?(caps))
     |> assign(:log_job_time_job_id, nil)
     |> assign(:log_job_time_client_name, "")
     |> assign(:job_time_started_at, "")
     |> assign(:job_time_ended_at, "")
     |> assign(:job_time_notes, "")
     |> assign(:sms_intake_href, Phone.sms_uri(sms_from))
     |> assign(:sms_intake_display, Phone.format_us_display(sms_from))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    if socket.assigns.live_action in [:new, :edit] and not socket.assigns.can_edit_jobs do
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You do not have permission to edit jobs.")
       |> Phoenix.LiveView.push_patch(to: ~p"/")}
    else
      {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :job, nil)
  end

  defp apply_action(socket, :new, _params) do
    bid = socket.assigns.current_business_id
    assign(socket, :job, %Job{business_id: bid})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    bid = socket.assigns.current_business_id
    assign(socket, :job, Jobs.get_job!(String.to_integer(id), bid))
  end

  @impl true
  def handle_info({:created, _job}, socket) do
    {:noreply, refresh_jobs(socket)}
  end

  def handle_info({:updated, _job}, socket) do
    {:noreply, refresh_jobs(socket)}
  end

  def handle_info({:deleted, _job}, socket) do
    {:noreply, refresh_jobs(socket)}
  end

  def handle_info({:time_entry_created, _entry}, socket) do
    {:noreply, refresh_time_entries(socket)}
  end

  def handle_info({:time_entry_updated, _entry}, socket) do
    {:noreply, refresh_time_entries(socket)}
  end

  def handle_info({:time_entry_deleted, _entry}, socket) do
    {:noreply, refresh_time_entries(socket)}
  end

  def handle_info({RompCrmWeb.JobFormComponent, {:saved, _job}}, socket) do
    {:noreply, refresh_jobs(socket)}
  end

  defp refresh_jobs(socket) do
    bid = socket.assigns.current_business_id
    assign(socket, :jobs, Jobs.list_jobs(bid))
  end

  defp refresh_time_entries(socket) do
    expanded_id = socket.assigns.expanded_job_id

    if expanded_id do
      bid = socket.assigns.current_business_id
      entries = TimeTracking.list_time_entries_for_job(expanded_id, bid)

      assign(
        socket,
        :expanded_time_entries,
        Map.put(socket.assigns.expanded_time_entries, expanded_id, entries)
      )
    else
      socket
    end
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:filter, String.to_existing_atom(status))
     |> refresh_jobs()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to delete jobs.")}
    else
      bid = socket.assigns.current_business_id
      user = socket.assigns.current_scope.user
      job = Jobs.get_job!(String.to_integer(id), bid)

      case Jobs.delete_job(job) do
        {:ok, _} ->
          BusinessAuditLogs.record(%{
            business_id: bid,
            actor_user_id: user.id,
            source: "web",
            action: "jobs.delete",
            entity_type: "jobs",
            entity_id: job.id,
            metadata: %{client_name: job.client_name}
          })

          {:noreply, refresh_jobs(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete that job.")}
      end
    end
  end

  def handle_event("open_job_time_log", %{"job_id" => job_id}, socket) do
    if not socket.assigns.can_log_job_time do
      {:noreply, put_flash(socket, :error, "You do not have permission to log time on jobs.")}
    else
      job_id = String.to_integer(job_id)
      bid = socket.assigns.current_business_id
      job = Jobs.get_job!(job_id, bid)
      {s, e} = JobTimeLogDefaults.default_datetime_local_pair()

      {:noreply,
       socket
       |> assign(:log_job_time_job_id, job_id)
       |> assign(:log_job_time_client_name, job.client_name || "Job")
       |> assign(:job_time_started_at, s)
       |> assign(:job_time_ended_at, e)
       |> assign(:job_time_notes, "")}
    end
  end

  def handle_event("close_job_time_log", _params, socket) do
    {:noreply,
     socket
     |> assign(:log_job_time_job_id, nil)
     |> assign(:log_job_time_client_name, "")
     |> assign(:job_time_started_at, "")
     |> assign(:job_time_ended_at, "")
     |> assign(:job_time_notes, "")}
  end

  def handle_event("job_time_field", params, socket) do
    started = Map.get(params, "started_at", socket.assigns.job_time_started_at)
    ended = Map.get(params, "ended_at", socket.assigns.job_time_ended_at)
    notes = Map.get(params, "notes", socket.assigns.job_time_notes)

    {:noreply,
     socket
     |> assign(:job_time_started_at, started)
     |> assign(:job_time_ended_at, ended)
     |> assign(:job_time_notes, notes)}
  end

  def handle_event("save_job_time_log", params, socket) do
    if not socket.assigns.can_log_job_time do
      {:noreply, put_flash(socket, :error, "You do not have permission to log time on jobs.")}
    else
      job_id = socket.assigns.log_job_time_job_id
      bid = socket.assigns.current_business_id
      user = socket.assigns.current_scope.user

      if is_nil(job_id) do
        {:noreply, socket}
      else
        started_s = Map.get(params, "started_at", socket.assigns.job_time_started_at)
        ended_s = Map.get(params, "ended_at", socket.assigns.job_time_ended_at)

        notes =
          (Map.get(params, "notes") || socket.assigns.job_time_notes)
          |> to_string()
          |> String.trim()

        case {DatetimeLocal.parse(started_s), DatetimeLocal.parse(ended_s)} do
          {{:error, :missing}, _} ->
            {:noreply, put_flash(socket, :error, "Start and end are required.")}

          {_, {:error, :missing}} ->
            {:noreply, put_flash(socket, :error, "Start and end are required.")}

          {{:error, _}, _} ->
            {:noreply, put_flash(socket, :error, "Invalid start time.")}

          {_, {:error, _}} ->
            {:noreply, put_flash(socket, :error, "Invalid end time.")}

          {{:ok, started_at}, {:ok, ended_at}} ->
            if NaiveDateTime.compare(ended_at, started_at) != :gt do
              {:noreply, put_flash(socket, :error, "End time must be after start time.")}
            else
              attrs = %{
                business_id: bid,
                job_id: job_id,
                started_at: started_at,
                ended_at: ended_at,
                notes: if(notes == "", do: nil, else: notes)
              }

              case TimeTracking.create_time_entry(attrs) do
                {:ok, entry} ->
                  BusinessAuditLogs.record(%{
                    business_id: bid,
                    actor_user_id: user.id,
                    source: "web",
                    action: "time_entries.create",
                    entity_type: "time_entries",
                    entity_id: entry.id,
                    metadata: %{job_id: job_id, source: "job_hours_form"}
                  })

                  {:noreply,
                   socket
                   |> assign(:log_job_time_job_id, nil)
                   |> assign(:log_job_time_client_name, "")
                   |> assign(:job_time_started_at, "")
                   |> assign(:job_time_ended_at, "")
                   |> assign(:job_time_notes, "")
                   |> put_flash(:info, "Job hours saved.")
                   |> refresh_time_entries()
                   |> refresh_jobs()}

                {:error, %Ecto.Changeset{} = cs} ->
                  msg =
                    cs.errors
                    |> Enum.map(fn {k, {m, _}} -> "#{k} #{m}" end)
                    |> Enum.join("; ")

                  {:noreply,
                   put_flash(
                     socket,
                     :error,
                     if(msg != "", do: msg, else: "Could not save hours.")
                   )}
              end
            end
        end
      end
    end
  end

  def handle_event("inline_job_update", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(params["job_id"])
      field = to_string(params["field"] || "")
      bid = socket.assigns.current_business_id

      if inline_job_field_allowed?(field) do
        key = "job_#{job_id}_#{field}"
        raw = Map.get(params, key)
        attrs = build_inline_job_update_attrs(field, raw)

        if attrs == %{} do
          {:noreply, socket}
        else
          case Jobs.get_job(job_id, bid) do
            nil ->
              {:noreply, put_flash(socket, :error, "Job not found.")}

            job ->
              case Jobs.update_job(job, attrs) do
                {:ok, _} ->
                  {:noreply, refresh_jobs(socket)}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "Could not save that change.")}
              end
          end
        end
      else
        {:noreply, put_flash(socket, :error, "Invalid field.")}
      end
    end
  end

  def handle_event("toggle_row", %{"id" => id}, socket) do
    id = String.to_integer(id)
    bid = socket.assigns.current_business_id

    expanded =
      if socket.assigns.expanded_job_id == id do
        nil
      else
        id
      end

    entries_map =
      if expanded do
        entries = TimeTracking.list_time_entries_for_job(expanded, bid)
        Map.put(socket.assigns.expanded_time_entries, expanded, entries)
      else
        socket.assigns.expanded_time_entries
      end

    {:noreply,
     socket
     |> assign(:expanded_job_id, expanded)
     |> assign(:expanded_time_entries, entries_map)
     |> refresh_jobs()}
  end

  def handle_event(
        "toggle_work_item_completed",
        %{"job_id" => jid, "work_item_id" => wi_id},
        socket
      ) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(jid)
      wi_id = String.to_integer(wi_id)
      bid = socket.assigns.current_business_id

      case Jobs.get_job(job_id, bid) do
        nil ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        job ->
          row = Enum.find(job.work_items || [], &(&1.id == wi_id))

          case row do
            nil ->
              {:noreply, put_flash(socket, :error, "Work item not found.")}

            wi ->
              case Jobs.update_job_work_item(job, wi_id, %{completed: not wi.completed}) do
                {:ok, _} ->
                  {:noreply, refresh_jobs(socket)}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "Could not update work item.")}
              end
          end
      end
    end
  end

  def handle_event("work_item_scheduled_on", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(params["job_id"])
      wi_id = String.to_integer(params["work_item_id"])
      bid = socket.assigns.current_business_id
      key = "work_item_#{wi_id}_scheduled_on"
      raw = params |> Map.get(key, "") |> to_string() |> String.trim()

      scheduled_on =
        case raw do
          "" ->
            nil

          s ->
            case Date.from_iso8601(s) do
              {:ok, d} -> d
              _ -> nil
            end
        end

      case Jobs.get_job(job_id, bid) do
        nil ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        job ->
          case Jobs.update_job_work_item(job, wi_id, %{scheduled_on: scheduled_on}) do
            {:ok, _} -> {:noreply, refresh_jobs(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update date.")}
          end
      end
    end
  end

  def handle_event("work_item_title", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(params["job_id"])
      wi_id = String.to_integer(params["work_item_id"])
      bid = socket.assigns.current_business_id
      key = "work_item_#{wi_id}_title"
      title = params |> Map.get(key, "") |> to_string() |> String.trim()

      if title == "" do
        {:noreply, put_flash(socket, :error, "Work item title cannot be empty.")}
      else
        case Jobs.get_job(job_id, bid) do
          nil ->
            {:noreply, put_flash(socket, :error, "Job not found.")}

          job ->
            case Jobs.update_job_work_item(job, wi_id, %{title: title}) do
              {:ok, _} ->
                {:noreply, refresh_jobs(socket)}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not update work item title.")}
            end
        end
      end
    end
  end

  def handle_event("delete_work_item", %{"job_id" => jid, "work_item_id" => wi_id}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(jid)
      wi_id = String.to_integer(wi_id)
      bid = socket.assigns.current_business_id

      case Jobs.get_job(job_id, bid) do
        nil ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        job ->
          case Jobs.delete_job_work_item(job, wi_id) do
            {:ok, _} -> {:noreply, refresh_jobs(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete work item.")}
          end
      end
    end
  end

  def handle_event("toggle_material_completed", %{"job_id" => jid, "material_id" => mid}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(jid)
      mid = String.to_integer(mid)
      bid = socket.assigns.current_business_id

      case Jobs.get_job(job_id, bid) do
        nil ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        job ->
          row = Enum.find(job.materials || [], &(&1.id == mid))

          case row do
            nil ->
              {:noreply, put_flash(socket, :error, "Material not found.")}

            m ->
              case Jobs.update_job_material(job, mid, %{completed: not m.completed}) do
                {:ok, _} -> {:noreply, refresh_jobs(socket)}
                {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update material.")}
              end
          end
      end
    end
  end

  def handle_event("material_quantity", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(params["job_id"])
      mid = String.to_integer(params["material_id"])
      bid = socket.assigns.current_business_id
      key = "material_#{mid}_quantity"
      raw = params |> Map.get(key, "") |> to_string() |> String.trim()

      qty =
        case Float.parse(raw) do
          {f, _} -> f
          :error -> nil
        end

      if qty == nil or qty <= 0 do
        {:noreply, put_flash(socket, :error, "Enter a quantity greater than zero.")}
      else
        case Jobs.get_job(job_id, bid) do
          nil ->
            {:noreply, put_flash(socket, :error, "Job not found.")}

          job ->
            case Jobs.update_job_material(job, mid, %{quantity: qty}) do
              {:ok, _} -> {:noreply, refresh_jobs(socket)}
              {:error, _} -> {:noreply, put_flash(socket, :error, "Invalid quantity.")}
            end
        end
      end
    end
  end

  def handle_event("material_description", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(params["job_id"])
      mid = String.to_integer(params["material_id"])
      bid = socket.assigns.current_business_id
      key = "material_#{mid}_description"
      desc = params |> Map.get(key, "") |> to_string() |> String.trim()

      if desc == "" do
        {:noreply, put_flash(socket, :error, "Material description cannot be empty.")}
      else
        case Jobs.get_job(job_id, bid) do
          nil ->
            {:noreply, put_flash(socket, :error, "Job not found.")}

          job ->
            case Jobs.update_job_material(job, mid, %{description: desc}) do
              {:ok, _} ->
                {:noreply, refresh_jobs(socket)}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not update material description.")}
            end
        end
      end
    end
  end

  def handle_event("material_unit_price", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(params["job_id"])
      mid = String.to_integer(params["material_id"])
      bid = socket.assigns.current_business_id
      key = "material_#{mid}_unit_price"
      raw = params |> Map.get(key, "") |> to_string() |> String.trim()

      parsed =
        case raw do
          "" ->
            {:ok, nil}

          s ->
            case Float.parse(s) do
              {f, _} -> {:ok, f}
              :error -> :error
            end
        end

      case {Jobs.get_job(job_id, bid), parsed} do
        {nil, _} ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        {_job, :error} ->
          {:noreply, put_flash(socket, :error, "Enter a valid price or leave the field empty.")}

        {job, {:ok, unit_price}} ->
          case Jobs.update_job_material(job, mid, %{unit_price: unit_price}) do
            {:ok, _} -> {:noreply, refresh_jobs(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update price.")}
          end
      end
    end
  end

  def handle_event("delete_material", %{"job_id" => jid, "material_id" => mid}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = String.to_integer(jid)
      mid = String.to_integer(mid)
      bid = socket.assigns.current_business_id

      case Jobs.get_job(job_id, bid) do
        nil ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        job ->
          case Jobs.delete_job_material(job, mid) do
            {:ok, _} -> {:noreply, refresh_jobs(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete material.")}
          end
      end
    end
  end

  defp inline_job_field_allowed?(f)
       when f in ~w(client_name address phone work_description notes referred_by next_action priority status scheduled_on),
       do: true

  defp inline_job_field_allowed?(_), do: false

  defp build_inline_job_update_attrs("priority", raw) when raw in ~w(high normal),
    do: %{"priority" => raw}

  defp build_inline_job_update_attrs("priority", _), do: %{}

  defp build_inline_job_update_attrs("status", raw)
       when raw in ~w(lead pending in_progress done),
       do: %{"status" => raw}

  defp build_inline_job_update_attrs("status", _), do: %{}

  defp build_inline_job_update_attrs("scheduled_on", raw) do
    s = raw |> to_string() |> String.trim()

    case s do
      "" ->
        %{"scheduled_on" => ""}

      _ ->
        case Date.from_iso8601(s) do
          {:ok, _} -> %{"scheduled_on" => s}
          _ -> %{}
        end
    end
  end

  defp build_inline_job_update_attrs(field, raw)
       when field in ~w(client_name address phone work_description notes referred_by next_action) do
    %{field => raw |> to_string()}
  end

  defp build_inline_job_update_attrs(_, _), do: %{}

  defp visible_jobs(jobs, :all), do: jobs
  defp visible_jobs(jobs, status), do: Enum.filter(jobs, &(&1.status == status))

  defp status_label(:lead), do: "Lead"
  defp status_label(:pending), do: "Pending"
  defp status_label(:in_progress), do: "In Progress"
  defp status_label(:done), do: "Done"

  defp status_class(:lead), do: "bg-blue-100 text-blue-800"
  defp status_class(:pending), do: "bg-amber-100 text-amber-800"
  defp status_class(:in_progress), do: "bg-green-100 text-green-800"
  defp status_class(:done), do: "bg-gray-100 text-gray-600"

  defp priority_class(:high), do: "bg-red-100 text-red-800"
  defp priority_class(:normal), do: ""

  defp count_for(jobs, :all), do: length(jobs)
  defp count_for(jobs, status), do: Enum.count(jobs, &(&1.status == status))

  defp expanded?(expanded_job_id, job_id), do: expanded_job_id == job_id

  defp display(nil), do: "—"
  defp display(""), do: "—"
  defp display(value), do: value

  defp time_entries_for(expanded_map, job_id) do
    Map.get(expanded_map, job_id, [])
  end

  defp format_time_entry_date(%NaiveDateTime{} = dt) do
    "#{dt.month}/#{dt.day}/#{rem(dt.year, 100)}"
  end

  defp format_time_entry_time(%NaiveDateTime{} = dt) do
    hour = dt.hour
    min = String.pad_leading(to_string(dt.minute), 2, "0")

    {h12, ampm} =
      if hour >= 12,
        do: {rem(hour, 12) |> then(&if &1 == 0, do: 12, else: &1), "PM"},
        else: {if(hour == 0, do: 12, else: hour), "AM"}

    "#{h12}:#{min} #{ampm}"
  end
end
