defmodule RompCrmWeb.JobsLive do
  use RompCrmWeb, :live_view

  import RompCrmWeb.JobExpandLists
  import RompCrmWeb.JobExpandedInlineFields
  import RompCrmWeb.JobDeleteBar, only: [job_delete_bar: 1]

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.TimeTracking
  alias RompCrm.TimeTracking.TimeEntry
  alias RompCrmWeb.DatetimeLocal
  alias RompCrmWeb.JobTimeLogDefaults
  alias RompCrmWeb.JobExpandEditKeys, as: JEK

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket) do
      Jobs.subscribe(bid)
      TimeTracking.subscribe(bid)
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
     |> assign(:log_time_entry_id, nil)
     |> assign(:job_delete_steps, %{})
     |> assign(:job_expand_editing, MapSet.new())}
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
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end

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

  def handle_event("job_delete_advance", %{"id" => id}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to delete jobs.")}
    else
      jid = String.to_integer(id)
      bid = socket.assigns.current_business_id
      steps = socket.assigns.job_delete_steps
      step = Map.get(steps, jid, 0)

      cond do
        step < 2 ->
          {:noreply, assign(socket, :job_delete_steps, Map.put(steps, jid, step + 1))}

        true ->
          user = socket.assigns.current_scope.user
          job = Jobs.get_job!(jid, bid)

          case Jobs.delete_job(job) do
            {:ok, _} ->
              BusinessAuditLogs.record(%{
                business_id: bid,
                actor_user_id: user.id,
                source: "web",
                action: "jobs.delete",
                entity_type: "jobs",
                entity_id: job.id,
                metadata: %{
                  client_name: job.client_name,
                  job_id: job.id,
                  changes: [%{type: "job_deleted", job_id: job.id, client_name: job.client_name}]
                }
              })

              expanded = socket.assigns.expanded_job_id

              {:noreply,
               socket
               |> assign(:expanded_job_id, if(expanded == jid, do: nil, else: expanded))
               |> assign(:job_delete_steps, Map.delete(steps, jid))
               |> put_flash(:info, "Job deleted.")
               |> refresh_jobs()}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not delete that job.")}
          end
      end
    end
  end

  def handle_event("job_delete_cancel", %{"id" => id}, socket) do
    jid = String.to_integer(id)
    steps = Map.delete(socket.assigns.job_delete_steps, jid)
    {:noreply, assign(socket, :job_delete_steps, steps)}
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
       |> assign(:log_time_entry_id, nil)
       |> assign(:log_job_time_client_name, job.client_name || "Job")
       |> assign(:job_time_started_at, s)
       |> assign(:job_time_ended_at, e)
       |> assign(:job_time_notes, "")}
    end
  end

  def handle_event("open_edit_job_time_log", %{"job_id" => job_id, "time_entry_id" => te_id}, socket) do
    if not socket.assigns.can_log_job_time do
      {:noreply, put_flash(socket, :error, "You do not have permission to log time on jobs.")}
    else
      job_id = String.to_integer(job_id)
      te_id = String.to_integer(te_id)
      bid = socket.assigns.current_business_id
      job = Jobs.get_job!(job_id, bid)
      entry = TimeTracking.get_time_entry!(te_id, bid)

      if entry.job_id != job_id do
        {:noreply, put_flash(socket, :error, "That time entry does not belong to this job.")}
      else
        started_s = JobTimeLogDefaults.to_datetime_local(entry.started_at)

        ended_s =
          case entry.ended_at do
            %NaiveDateTime{} = e -> JobTimeLogDefaults.to_datetime_local(e)
            _ -> ""
          end

        notes = entry.notes || ""

        {:noreply,
         socket
         |> assign(:log_job_time_job_id, job_id)
         |> assign(:log_time_entry_id, entry.id)
         |> assign(:log_job_time_client_name, job.client_name || "Job")
         |> assign(:job_time_started_at, started_s)
         |> assign(:job_time_ended_at, ended_s)
         |> assign(:job_time_notes, notes)}
      end
    end
  end

  def handle_event("delete_time_entry", %{"job_id" => job_id, "id" => te_id}, socket) do
    if not socket.assigns.can_log_job_time do
      {:noreply, put_flash(socket, :error, "You do not have permission to change job hours.")}
    else
      job_id = String.to_integer(job_id)
      te_id = String.to_integer(te_id)
      bid = socket.assigns.current_business_id
      user = socket.assigns.current_scope.user

      entry = TimeTracking.get_time_entry!(te_id, bid)

      if entry.job_id != job_id do
        {:noreply, put_flash(socket, :error, "That time entry does not belong to this job.")}
      else
        case TimeTracking.delete_time_entry(entry) do
          {:ok, _} ->
            BusinessAuditLogs.record(%{
              business_id: bid,
              actor_user_id: user.id,
              source: "web",
              action: "time_entries.delete",
              entity_type: "time_entries",
              entity_id: te_id,
              metadata: %{job_id: job_id, source: "job_hours_list"}
            })

            {:noreply,
             socket
             |> put_flash(:info, "Job hours removed.")
             |> refresh_time_entries()
             |> refresh_jobs()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not remove those hours.")}
        end
      end
    end
  end

  def handle_event("close_job_time_log", _params, socket) do
    {:noreply,
     socket
     |> assign(:log_job_time_job_id, nil)
     |> assign(:log_time_entry_id, nil)
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
      te_id = socket.assigns.log_time_entry_id

      if is_nil(job_id) do
        {:noreply, socket}
      else
        started_s = Map.get(params, "started_at", socket.assigns.job_time_started_at)
        ended_s = Map.get(params, "ended_at", socket.assigns.job_time_ended_at)

        notes =
          (Map.get(params, "notes") || socket.assigns.job_time_notes)
          |> to_string()
          |> String.trim()

        entry_for_resolve =
          if is_integer(te_id) do
            TimeTracking.get_time_entry!(te_id, bid)
          else
            nil
          end

        with {:ok, started_at} <- DatetimeLocal.parse(started_s),
             {:ok, ended_at} <- resolve_job_time_ended(ended_s, entry_for_resolve) do
          cond do
            is_nil(ended_at) ->
              {:noreply,
               save_job_time_log_apply(socket, job_id, bid, user, te_id, started_at, nil, notes)}

            NaiveDateTime.compare(ended_at, started_at) != :gt ->
              {:noreply, put_flash(socket, :error, "End time must be after start time.")}

            true ->
              {:noreply,
               save_job_time_log_apply(socket, job_id, bid, user, te_id, started_at, ended_at, notes)}
          end
        else
          {:error, :missing} ->
            {:noreply, put_flash(socket, :error, "Start time is required.")}

          {:error, :ended_required} ->
            {:noreply, put_flash(socket, :error, "End time is required for completed hours.")}

          {:error, :missing_ended} ->
            {:noreply, put_flash(socket, :error, "Start and end are required.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Invalid start or end time.")}
        end
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

    steps_cleared =
      case expanded do
        nil -> %{}
        eid -> Map.take(socket.assigns.job_delete_steps, [eid])
      end

    {:noreply,
     socket
     |> assign(:expanded_job_id, expanded)
     |> assign(:expanded_time_entries, entries_map)
     |> assign(:job_expand_editing, MapSet.new())
     |> assign(:job_delete_steps, steps_cleared)
     |> refresh_jobs()}
  end

  def handle_event("job_expand_edit_start", %{"key" => key}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      keys = MapSet.put(socket.assigns.job_expand_editing, key)
      {:noreply, assign(socket, :job_expand_editing, keys)}
    end
  end

  def handle_event("job_expand_edit_cancel", %{"key" => key}, socket) do
    keys = MapSet.delete(socket.assigns.job_expand_editing, key)
    {:noreply, assign(socket, :job_expand_editing, keys)}
  end

  def handle_event("job_expand_commit_job", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = parse_id_param(params["job_id"])
      field = to_string(params["field"] || "")
      raw = Map.get(params, "value")

      attrs =
        if field == "scheduled_on" do
          build_job_schedule_update_attrs(params)
        else
          build_inline_job_update_attrs(field, raw)
        end

      cond do
        job_id == nil ->
          {:noreply, put_flash(socket, :error, "Invalid request.")}

        not inline_job_field_allowed?(field) ->
          {:noreply, put_flash(socket, :error, "Invalid field.")}

        true ->
          edit_key = JEK.job(job_id, field)
          bid = socket.assigns.current_business_id

          if attrs == %{} do
            {:noreply, drop_expand_edit(socket, edit_key)}
          else
            case Jobs.get_job(job_id, bid) do
              nil ->
                {:noreply, put_flash(socket, :error, "Job not found.")}

              job ->
                case Jobs.update_job(job, attrs) do
                  {:ok, _} ->
                    {:noreply, socket |> refresh_jobs() |> drop_expand_edit(edit_key)}

                  {:error, _} ->
                    {:noreply, put_flash(socket, :error, "Could not save that change.")}
                end
            end
          end
      end
    end
  end

  def handle_event("job_expand_commit_wi_row", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = parse_id_param(params["job_id"])
      wi_id = parse_id_param(params["work_item_id"])
      title = params |> Map.get("title", "") |> to_string() |> String.trim()
      scheduled_on = parse_scheduled_on_form_param(params["scheduled_on"])
      scheduled_time_raw = params |> Map.get("scheduled_time", "") |> to_string() |> String.trim()

      scheduled_time =
        case scheduled_time_raw do
          "" -> nil
          s -> parse_time_for_work_item(s)
        end

      cond do
        job_id == nil or wi_id == nil ->
          {:noreply, put_flash(socket, :error, "Invalid request.")}

        title == "" ->
          {:noreply, put_flash(socket, :error, "Work item title cannot be empty.")}

        true ->
          edit_key = JEK.wi_edit(wi_id)
          bid = socket.assigns.current_business_id

          case Jobs.get_job(job_id, bid) do
            nil ->
              {:noreply, put_flash(socket, :error, "Job not found.")}

            job ->
              case Jobs.update_job_work_item(job, wi_id, %{
                     title: title,
                     scheduled_on: scheduled_on,
                     scheduled_time: scheduled_time
                   }) do
                {:ok, _} -> {:noreply, socket |> refresh_jobs() |> drop_expand_edit(edit_key)}
                {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update work item.")}
              end
          end
      end
    end
  end

  def handle_event("job_expand_commit_material_row", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = parse_id_param(params["job_id"])
      mid = parse_id_param(params["material_id"])
      desc = params |> Map.get("description", "") |> to_string() |> String.trim()
      qty_raw = params |> Map.get("quantity", "") |> to_string() |> String.trim()

      qty =
        case Float.parse(qty_raw) do
          {f, _} -> f
          :error -> nil
        end

      cond do
        job_id == nil or mid == nil ->
          {:noreply, put_flash(socket, :error, "Invalid request.")}

        desc == "" ->
          {:noreply, put_flash(socket, :error, "Material description cannot be empty.")}

        qty == nil or qty <= 0 ->
          {:noreply, put_flash(socket, :error, "Enter a quantity greater than zero.")}

        true ->
          edit_key = JEK.mat_edit(mid)
          bid = socket.assigns.current_business_id

          case Jobs.get_job(job_id, bid) do
            nil ->
              {:noreply, put_flash(socket, :error, "Job not found.")}

            job ->
              row = Enum.find(job.materials || [], &(&1.id == mid))

              case Jobs.update_job_material(job, mid, %{quantity: qty, description: desc}) do
                {:ok, _} ->
                  audit_material_change(socket, job, row, desc, qty, "job_materials.update")
                  {:noreply, socket |> refresh_jobs() |> drop_expand_edit(edit_key)}

                {:error, _} ->
                  {:noreply, put_flash(socket, :error, "Could not update material.")}
              end
          end
      end
    end
  end

  def handle_event("toggle_work_item_completed", %{"job_id" => jid, "work_item_id" => wi_id}, socket) do
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
                {:ok, _} -> {:noreply, refresh_jobs(socket)}
                {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update work item.")}
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
          row = Enum.find(job.materials || [], &(&1.id == mid))

          case Jobs.delete_job_material(job, mid) do
            {:ok, _} ->
              audit_material_removed(socket, job, row)
              {:noreply, refresh_jobs(socket)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not delete material.")}
          end
      end
    end
  end

  defp resolve_job_time_ended(ended_s, entry) do
    ended_s = ended_s |> to_string() |> String.trim()

    cond do
      ended_s != "" ->
        DatetimeLocal.parse(ended_s)

      entry == nil ->
        {:error, :missing_ended}

      entry.ended_at == nil ->
        {:ok, nil}

      true ->
        {:error, :ended_required}
    end
  end

  defp save_job_time_log_apply(socket, job_id, bid, user, te_id, started_at, ended_at, notes) do
    notes_field = if(notes == "", do: nil, else: notes)

    result =
      if is_integer(te_id) do
        entry = TimeTracking.get_time_entry!(te_id, bid)

        if entry.job_id != job_id do
          {:error, :wrong_job}
        else
          TimeTracking.update_time_entry(entry, %{
            started_at: started_at,
            ended_at: ended_at,
            notes: notes_field
          })
        end
      else
        TimeTracking.create_time_entry(%{
          business_id: bid,
          job_id: job_id,
          started_at: started_at,
          ended_at: ended_at,
          notes: notes_field
        })
      end

    case result do
      {:error, :wrong_job} ->
        {:noreply, put_flash(socket, :error, "That entry does not belong to this job.")}

      {:ok, entry} ->
        action =
          if is_integer(te_id),
            do: "time_entries.update",
            else: "time_entries.create"

        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: user.id,
          source: "web",
          action: action,
          entity_type: "time_entries",
          entity_id: entry.id,
          metadata: %{job_id: job_id, source: "job_hours_form"}
        })

        msg = if is_integer(te_id), do: "Job hours updated.", else: "Job hours saved."

        {:noreply,
         socket
         |> assign(:log_job_time_job_id, nil)
         |> assign(:log_time_entry_id, nil)
         |> assign(:log_job_time_client_name, "")
         |> assign(:job_time_started_at, "")
         |> assign(:job_time_ended_at, "")
         |> assign(:job_time_notes, "")
         |> put_flash(:info, msg)
         |> refresh_time_entries()
         |> refresh_jobs()}

      {:error, %Ecto.Changeset{} = cs} ->
        msg =
          cs.errors
          |> Enum.map(fn {k, {m, _}} -> "#{k} #{m}" end)
          |> Enum.join("; ")

        {:noreply, put_flash(socket, :error, if(msg != "", do: msg, else: "Could not save hours."))}
    end
  end

  defp drop_expand_edit(socket, key) do
    assign(socket, :job_expand_editing, MapSet.delete(socket.assigns.job_expand_editing, key))
  end

  defp audit_material_change(_socket, _job, nil, _desc, _qty, _action), do: :ok

  defp audit_material_change(socket, job, before, desc, qty, action) do
    before_desc = if is_map(before), do: before.description, else: nil
    before_qty = if is_map(before), do: before.quantity, else: nil

    BusinessAuditLogs.record(%{
      business_id: socket.assigns.current_business_id,
      actor_user_id: socket.assigns.current_scope.user.id,
      source: "web",
      action: action,
      entity_type: "job_materials",
      entity_id: if(is_map(before), do: before.id, else: nil),
      metadata: %{
        job_id: job.id,
        client_name: job.client_name,
        changes: [
          %{
            type: "material_updated",
            material_id: if(is_map(before), do: before.id, else: nil),
            before: %{description: before_desc, quantity: before_qty},
            after_value: %{description: desc, quantity: qty}
          }
        ]
      }
    })
  end

  defp audit_material_removed(_socket, _job, nil), do: :ok

  defp audit_material_removed(socket, job, m) do
    BusinessAuditLogs.record(%{
      business_id: socket.assigns.current_business_id,
      actor_user_id: socket.assigns.current_scope.user.id,
      source: "web",
      action: "job_materials.delete",
      entity_type: "job_materials",
      entity_id: m.id,
      metadata: %{
        job_id: job.id,
        client_name: job.client_name,
        changes: [
          %{
            type: "material_removed",
            material_id: m.id,
            description: m.description,
            quantity: m.quantity
          }
        ]
      }
    })
  end

  defp parse_scheduled_on_form_param(raw) do
    s = raw |> to_string() |> String.trim()

    case s do
      "" ->
        nil

      _ ->
        case Date.from_iso8601(s) do
          {:ok, d} -> d
          _ -> nil
        end
    end
  end

  defp build_job_schedule_update_attrs(params) do
    date_raw = params |> Map.get("value", "") |> to_string() |> String.trim()
    time_raw = params |> Map.get("scheduled_time", "") |> to_string() |> String.trim()

    cond do
      date_raw == "" ->
        %{"scheduled_on" => "", "scheduled_time" => ""}

      match?({:ok, _}, Date.from_iso8601(date_raw)) ->
        %{"scheduled_on" => date_raw, "scheduled_time" => time_raw}

      true ->
        %{}
    end
  end

  defp parse_time_for_work_item(s) when is_binary(s) do
    t = String.trim(s)

    cond do
      t == "" ->
        nil

      true ->
        case String.split(t, ":") do
          [hs, ms | _] ->
            with {h, _} <- Integer.parse(String.trim(hs)),
                 {m, _} <- Integer.parse(String.trim(ms)),
                 {:ok, time} <- Time.new(h, m, 0) do
              time
            else
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  defp parse_time_for_work_item(_), do: nil

  defp parse_id_param(v) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp inline_job_field_allowed?(f)
       when f in ~w(client_name address phone client_email work_description notes referred_by next_action priority status scheduled_on),
       do: true

  defp inline_job_field_allowed?(_), do: false

  defp build_inline_job_update_attrs("priority", raw) when raw in ~w(high normal), do: %{"priority" => raw}
  defp build_inline_job_update_attrs("priority", _), do: %{}

  defp build_inline_job_update_attrs("status", raw)
       when raw in ~w(lead pending in_progress done),
       do: %{"status" => raw}

  defp build_inline_job_update_attrs("status", _), do: %{}

  defp build_inline_job_update_attrs(field, raw)
       when field in ~w(client_name address phone client_email work_description notes referred_by next_action) do
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

  def delete_step_for(steps, job_id), do: Map.get(steps, job_id, 0)

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
