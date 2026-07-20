defmodule RompCrmWeb.JobsLive do
  use RompCrmWeb, :live_view

  import RompCrmWeb.JobExpandLists
  import RompCrmWeb.JobExpandedInlineFields
  import RompCrmWeb.JobDeleteBar, only: [job_delete_bar: 1]
  import RompCrmWeb.JobPrintButton, only: [job_print_button: 1]
  import RompCrmWeb.JobPhotosSection, only: [job_photos_section: 1]
  import RompCrmWeb.JobAddPhotosModal, only: [job_add_photos_modal: 1]
  import RompCrmWeb.JobPhotoViewerModal, only: [job_photo_viewer_modal: 1]

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses
  alias RompCrm.Clients
  alias RompCrm.Clients.ClientContact
  alias RompCrm.Clients.MatchSuggest
  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.TimeTracking
  alias RompCrm.TimeTracking.TimeEntry
  alias RompCrmWeb.DatetimeLocal
  alias RompCrmWeb.JobTimeLogDefaults
  alias RompCrmWeb.JobExpandEditKeys, as: JEK
  alias RompCrmWeb.JobsList
  alias RompCrmWeb.AddressFormHandlers
  alias RompCrm.ContactInfo

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
     |> assign(:sort_by, :name)
     |> assign(:show_address_primary, false)
     |> assign(:color_code_statuses, false)
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
     |> assign(:job_expand_editing, MapSet.new())
     |> assign(:address_suggestion, nil)
     |> assign(:add_photos_job_id, nil)
     |> assign(:add_photos_client_name, "")
     |> assign(:add_photos_saved_count, 0)
     |> assign(:photo_viewer_job_id, nil)
     |> assign(:photo_viewer_photo_id, nil)
     |> assign(:photo_delete_all_pending_job_id, nil)
     |> assign(:photo_delete_all_confirm_step, 0)
     |> assign(:pending_client_update, nil)
     |> assign(:client_match, nil)
     |> assign(:clients_for_picker, Clients.list_clients(bid))}
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
    socket
    |> assign(:job, nil)
    |> assign(:client_match, nil)
  end

  defp apply_action(socket, :new, params) do
    bid = socket.assigns.current_business_id
    job = build_new_job(bid, params)
    assign(socket, :job, job)
  end

  defp build_new_job(bid, params) do
    job = %Job{business_id: bid}

    case parse_id_param(params["client_id"]) do
      nil ->
        job

      client_id ->
        case Clients.get_client(client_id, bid) do
          nil ->
            job

          client ->
            contact = ClientContact.from_struct(client)

            job
            |> struct(contact)
            |> Map.put(:client_id, client.id)
            |> Map.put(:client, client)
        end
    end
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
    {:noreply, refresh_jobs(socket) |> assign(:client_match, nil)}
  end

  def handle_info({RompCrmWeb.JobFormComponent, {:job_save_requested, params, material_lines}}, socket) do
    handle_job_save_requested(socket, params, material_lines)
  end

  defp refresh_jobs(socket) do
    bid = socket.assigns.current_business_id

    socket
    |> assign(:jobs, Jobs.list_jobs(bid))
    |> assign(:clients_for_picker, Clients.list_clients(bid))
  end

  defp close_photo_viewer(socket) do
    socket
    |> assign(:photo_viewer_job_id, nil)
    |> assign(:photo_viewer_photo_id, nil)
  end

  defp step_photo_viewer(socket, delta) when delta in [-1, 1] do
    case viewer_job(socket) do
      nil ->
        socket

      job ->
        photos = job.photos || []
        pos = photo_viewer_position(photos, socket.assigns.photo_viewer_photo_id)

        case Enum.at(photos, pos - 1 + delta) do
          nil -> socket
          ph -> assign(socket, :photo_viewer_photo_id, ph.id)
        end
    end
  end

  defp viewer_job(%{assigns: %{photo_viewer_job_id: jid, jobs: jobs}}) when is_integer(jid) do
    Enum.find(jobs, &(&1.id == jid))
  end

  defp viewer_job(_), do: nil

  defp photo_viewer_position(photos, photo_id) when is_list(photos) do
    case Enum.find_index(photos, &(&1.id == photo_id)) do
      nil -> 1
      idx -> idx + 1
    end
  end

  defp photo_viewer_job_for_assigns(jobs, job_id) when is_integer(job_id) do
    Enum.find(jobs, &(&1.id == job_id))
  end

  defp photo_viewer_job_for_assigns(_, _), do: nil

  defp close_add_photos_modal(socket) do
    socket
    |> assign(:add_photos_job_id, nil)
    |> assign(:add_photos_client_name, "")
    |> assign(:add_photos_saved_count, 0)
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
    {:noreply, assign(socket, :filter, String.to_existing_atom(status))}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, assign(socket, :sort_by, String.to_existing_atom(sort))}
  end

  def handle_event("toggle_address_primary", _params, socket) do
    {:noreply, assign(socket, :show_address_primary, !socket.assigns.show_address_primary)}
  end

  def handle_event("toggle_color_code", _params, socket) do
    {:noreply, assign(socket, :color_code_statuses, !socket.assigns.color_code_statuses)}
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

      tz =
        socket.assigns.current_scope.user.sms_reminder_prefs_json
        |> RompCrm.Reminders.decode_prefs_json()
        |> Map.get("timezone", RompCrm.LocalWallClock.default_timezone())

      {s, e} = JobTimeLogDefaults.default_datetime_local_pair(tz)

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

  def handle_event("open_add_photos", %{"job_id" => job_id}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to upload photos.")}
    else
      job_id = String.to_integer(job_id)
      bid = socket.assigns.current_business_id
      job = Jobs.get_job!(job_id, bid)

      {:noreply,
       socket
       |> assign(:add_photos_job_id, job_id)
       |> assign(:add_photos_client_name, job.client_name || "Job")
       |> assign(:add_photos_saved_count, 0)
       |> assign(:expanded_job_id, job_id)}
    end
  end

  def handle_event("close_add_photos", _params, socket) do
    {:noreply, close_add_photos_modal(socket)}
  end

  def handle_event("job_photo_uploaded", %{"count" => count}, socket) do
    count =
      case Integer.parse(to_string(count)) do
        {n, _} when n > 0 -> n
        _ -> 1
      end

    {:noreply,
     socket
     |> assign(:add_photos_saved_count, socket.assigns.add_photos_saved_count + count)
     |> refresh_jobs()}
  end

  def handle_event("job_photo_upload_failed", _params, socket) do
    {:noreply, put_flash(socket, :error, "Could not save photo. Try again.")}
  end

  def handle_event("open_photo_viewer", %{"job_id" => jid, "photo_id" => pid}, socket) do
    jid = String.to_integer(jid)
    pid = String.to_integer(pid)

    {:noreply,
     socket
     |> assign(:photo_viewer_job_id, jid)
     |> assign(:photo_viewer_photo_id, pid)}
  end

  def handle_event("close_photo_viewer", _params, socket) do
    {:noreply, close_photo_viewer(socket)}
  end

  def handle_event("photo_viewer_nav", %{"job_id" => jid, "photo_id" => pid}, socket) do
    if pid in [nil, ""] do
      {:noreply, socket}
    else
      jid = String.to_integer(jid)
      pid = String.to_integer(pid)

      if socket.assigns.photo_viewer_job_id == jid do
        {:noreply, assign(socket, :photo_viewer_photo_id, pid)}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("photo_viewer_key", %{"key" => key}, socket) do
    case key do
      "left" -> {:noreply, step_photo_viewer(socket, -1)}
      "right" -> {:noreply, step_photo_viewer(socket, 1)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_job_photo", %{"job_id" => jid, "photo_id" => pid}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to delete photos.")}
    else
      jid = String.to_integer(jid)
      pid = String.to_integer(pid)
      bid = socket.assigns.current_business_id
      user = socket.assigns.current_scope.user
      job = Jobs.get_job!(jid, bid)
      viewer_open? = socket.assigns.photo_viewer_job_id == jid
      viewer_idx = if viewer_open?, do: photo_viewer_position(job.photos || [], pid), else: nil

      case Jobs.delete_job_photo(job, bid, pid) do
        {:ok, updated} ->
          BusinessAuditLogs.record(%{
            business_id: bid,
            actor_user_id: user.id,
            source: "web",
            action: "jobs.photos.delete",
            entity_type: "jobs",
            entity_id: jid,
            metadata: %{photo_id: pid}
          })

          socket =
            socket
            |> put_flash(:info, "Photo deleted.")
            |> refresh_jobs()
            |> then(fn sock ->
              if viewer_open? do
                photos = updated.photos || []

                cond do
                  photos == [] ->
                    close_photo_viewer(sock)

                  true ->
                    new_id =
                      case Enum.at(photos, (viewer_idx || 1) - 1) do
                        nil -> hd(photos).id
                        ph -> ph.id
                      end

                    assign(sock, :photo_viewer_photo_id, new_id)
                end
              else
                sock
              end
            end)

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete photo.")}
      end
    end
  end

  def handle_event("move_job_photo", %{"job_id" => jid, "photo_id" => pid, "direction" => dir}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to reorder photos.")}
    else
      jid = String.to_integer(jid)
      pid = String.to_integer(pid)
      bid = socket.assigns.current_business_id
      job = Jobs.get_job!(jid, bid)

      direction =
        case dir do
          "up" -> :up
          "down" -> :down
          _ -> nil
        end

      if is_nil(direction) do
        {:noreply, socket}
      else
        case Jobs.move_job_photo(job, bid, pid, direction) do
          {:ok, _} ->
            {:noreply, refresh_jobs(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not reorder photo.")}
        end
      end
    end
  end

  def handle_event("request_delete_all_job_photos", %{"job_id" => jid}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to delete photos.")}
    else
      {:noreply,
       socket
       |> assign(:photo_delete_all_pending_job_id, String.to_integer(jid))
       |> assign(:photo_delete_all_confirm_step, 1)}
    end
  end

  def handle_event("advance_delete_all_job_photos", %{"job_id" => jid}, socket) do
    jid = String.to_integer(jid)

    if socket.assigns.photo_delete_all_pending_job_id == jid and
         socket.assigns.photo_delete_all_confirm_step == 1 do
      {:noreply, assign(socket, :photo_delete_all_confirm_step, 2)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_delete_all_job_photos", _params, socket) do
    {:noreply,
     socket
     |> assign(:photo_delete_all_pending_job_id, nil)
     |> assign(:photo_delete_all_confirm_step, 0)}
  end

  def handle_event("delete_all_job_photos", %{"job_id" => jid}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to delete photos.")}
    else
      jid = String.to_integer(jid)

      if socket.assigns.photo_delete_all_pending_job_id != jid or
           socket.assigns.photo_delete_all_confirm_step != 2 do
        {:noreply, socket}
      else
        bid = socket.assigns.current_business_id
        user = socket.assigns.current_scope.user
        job = Jobs.get_job!(jid, bid)
        edit_key = JEK.photos_edit(jid)

        case Jobs.delete_all_job_photos(job, bid) do
          {:ok, _updated, count} ->
            BusinessAuditLogs.record(%{
              business_id: bid,
              actor_user_id: user.id,
              source: "web",
              action: "jobs.photos.delete_all",
              entity_type: "jobs",
              entity_id: jid,
              metadata: %{count: count}
            })

            socket =
              socket
              |> assign(:photo_delete_all_pending_job_id, nil)
              |> assign(:photo_delete_all_confirm_step, 0)
              |> assign(:job_expand_editing, MapSet.delete(socket.assigns.job_expand_editing, edit_key))
              |> close_photo_viewer()
              |> put_flash(:info, "Deleted #{count} photo(s).")
              |> refresh_jobs()

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete photos.")}
        end
      end
    end
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
              save_job_time_log_apply(socket, job_id, bid, user, te_id, started_at, nil, notes)

            NaiveDateTime.compare(ended_at, started_at) != :gt ->
              {:noreply, put_flash(socket, :error, "End time must be after start time.")}

            true ->
              save_job_time_log_apply(socket, job_id, bid, user, te_id, started_at, ended_at, notes)
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

    photo_delete_pending =
      case expanded do
        nil ->
          {nil, 0}

        eid when eid == socket.assigns.photo_delete_all_pending_job_id ->
          {eid, socket.assigns.photo_delete_all_confirm_step}

        _ ->
          {nil, 0}
      end

    {:noreply,
     socket
     |> assign(:expanded_job_id, expanded)
     |> assign(:expanded_time_entries, entries_map)
     |> assign(:job_expand_editing, MapSet.new())
     |> assign(:job_delete_steps, steps_cleared)
     |> assign(:photo_delete_all_pending_job_id, elem(photo_delete_pending, 0))
     |> assign(:photo_delete_all_confirm_step, elem(photo_delete_pending, 1))
     |> refresh_jobs()}
  end

  def handle_event("job_expand_edit_start", %{"key" => key}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      {:noreply, assign(socket, :job_expand_editing, MapSet.new([key]))}
    end
  end

  def handle_event("job_expand_edit_switch", %{"to_key" => key}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      {:noreply,
       socket
       |> assign(:job_expand_editing, MapSet.new([key]))
       |> assign(:address_suggestion, nil)}
    end
  end

  def handle_event("job_expand_edit_cancel", %{"key" => key}, socket) do
    keys = MapSet.delete(socket.assigns.job_expand_editing, key)

    {:noreply,
     socket
     |> assign(:job_expand_editing, keys)
     |> assign(:address_suggestion, nil)}
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

        match?({:invalid, _}, attrs) ->
          {:invalid, msg} = attrs
          {:noreply, put_flash(socket, :error, msg)}

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
                cond do
                  job.client_id && Clients.client_contact_job_field?(field) ->
                    case Clients.get_client(job.client_id, bid) do
                      nil ->
                        case Jobs.update_job(job, attrs) do
                          {:ok, _} ->
                            {:noreply, socket |> refresh_jobs() |> drop_expand_edit(edit_key)}

                          {:error, changeset} ->
                            msg = inline_field_error(changeset, field) || "Could not save that change."
                            {:noreply, put_flash(socket, :error, msg)}
                        end

                      client ->
                        job_count = Clients.count_linked_jobs(client)

                        {:noreply,
                         assign(socket, :pending_client_update, %{
                           job_id: job_id,
                           client_id: job.client_id,
                           client_name: client.client_name,
                           job_count: job_count,
                           attrs: attrs,
                           edit_key: edit_key,
                           kind: :field
                         })}
                    end

                  true ->
                    case Jobs.update_job(job, attrs) do
                      {:ok, _} ->
                        {:noreply, socket |> refresh_jobs() |> drop_expand_edit(edit_key)}

                      {:error, changeset} ->
                        msg = inline_field_error(changeset, field) || "Could not save that change."
                        {:noreply, put_flash(socket, :error, msg)}
                    end
                end
            end
          end
      end
    end
  end

  def handle_event("confirm_client_update", _, socket) do
    case socket.assigns.pending_client_update do
      %{client_id: cid, attrs: attrs, edit_key: edit_key} = pending ->
        bid = socket.assigns.current_business_id

        case Clients.get_client(cid, bid) do
          nil ->
            {:noreply, put_flash(socket, :error, "Client not found.") |> assign(:pending_client_update, nil)}

          client ->
            case Clients.update_client_and_sync_jobs(client, attrs) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> assign(:pending_client_update, nil)
                 |> refresh_jobs()
                 |> drop_expand_edit(edit_key)
                 |> maybe_clear_address_suggestion(pending)}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not update client.")}
            end
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_client_update", _, socket) do
    pending = socket.assigns.pending_client_update
    edit_key = pending && pending.edit_key

    socket =
      socket
      |> assign(:pending_client_update, nil)
      |> maybe_clear_address_suggestion(pending)

    socket =
      if edit_key do
        drop_expand_edit(socket, edit_key)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("pick_client_match", %{"client_id" => id}, socket) do
    case socket.assigns.client_match do
      %{params: params, material_lines: lines} ->
        bid = socket.assigns.current_business_id

        case Clients.get_client(parse_id_param(id), bid) do
          nil ->
            {:noreply, put_flash(socket, :error, "Client not found.")}

          client ->
            finish_job_create(socket, params, lines, client.id, client)
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_new_client_for_job", _, socket) do
    case socket.assigns.client_match do
      %{params: params, material_lines: lines} ->
        finish_job_create(socket, params, lines, nil, nil)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_client_match", _, socket) do
    {:noreply, assign(socket, :client_match, nil)}
  end

  def handle_event("job_expand_commit_address", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = parse_id_param(params["job_id"])
      attrs = AddressFormHandlers.job_address_attrs_from_params(params)
      edit_key = JEK.job(job_id, "address")
      bid = socket.assigns.current_business_id

      cond do
        job_id == nil ->
          {:noreply, put_flash(socket, :error, "Invalid request.")}

        attrs == %{} ->
          {:noreply, drop_expand_edit(socket, edit_key) |> assign(:address_suggestion, nil)}

        true ->
          case Jobs.get_job(job_id, bid) do
            nil ->
              {:noreply, put_flash(socket, :error, "Job not found.")}

            job ->
              cond do
                job.client_id ->
                  case Clients.get_client(job.client_id, bid) do
                    nil ->
                      case Jobs.update_job(job, attrs) do
                        {:ok, _} ->
                          {:noreply,
                           socket
                           |> refresh_jobs()
                           |> drop_expand_edit(edit_key)
                           |> assign(:address_suggestion, nil)}

                        {:error, _} ->
                          {:noreply, put_flash(socket, :error, "Could not save that address.")}
                      end

                    client ->
                      {:noreply,
                       assign(socket, :pending_client_update, %{
                         job_id: job_id,
                         client_id: job.client_id,
                         client_name: client.client_name,
                         job_count: Clients.count_linked_jobs(client),
                         attrs: attrs,
                         edit_key: edit_key,
                         kind: :address
                       })}
                  end

                true ->
                  case Jobs.update_job(job, attrs) do
                    {:ok, _} ->
                      {:noreply,
                       socket
                       |> refresh_jobs()
                       |> drop_expand_edit(edit_key)
                       |> assign(:address_suggestion, nil)}

                    {:error, _} ->
                      {:noreply, put_flash(socket, :error, "Could not save that address.")}
                  end
              end
          end
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

      {:noreply,
       socket
       |> assign(:address_suggestion, nil)
       |> push_event("address_fill", %{part: part, fields: fill})}
    else
      {:noreply, socket}
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

  def handle_event("add_work_item", %{"job_id" => jid}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit jobs.")}
    else
      job_id = parse_id_param(jid)
      bid = socket.assigns.current_business_id

      case Jobs.get_job(job_id, bid) do
        nil ->
          {:noreply, put_flash(socket, :error, "Job not found.")}

        job ->
          case Jobs.add_job_work_item(job, %{title: ""}) do
            {:ok, {_job, wi}} ->
              edit_key = JEK.wi_edit(wi.id)

              {:noreply,
               socket
               |> refresh_jobs()
               |> assign(:expanded_job_id, job_id)
               |> assign(:job_expand_editing, MapSet.new([edit_key]))}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not add work item.")}
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
       when f in ~w(client_name address phone client_email work_description customer_comments notes referred_by next_action priority status scheduled_on),
       do: true

  defp inline_job_field_allowed?(_), do: false

  defp build_inline_job_update_attrs("priority", raw) when raw in ~w(high normal), do: %{"priority" => raw}
  defp build_inline_job_update_attrs("priority", _), do: %{}

  defp build_inline_job_update_attrs("status", raw)
       when raw in ~w(lead pending in_progress done),
       do: %{"status" => raw}

  defp build_inline_job_update_attrs("status", _), do: %{}

  defp build_inline_job_update_attrs("phone", raw) do
    case ContactInfo.normalize_phone(to_string(raw || "")) do
      {:ok, nil} -> %{"phone" => nil}
      {:ok, phone} -> %{"phone" => phone}
      {:error, msg} -> {:invalid, msg}
    end
  end

  defp build_inline_job_update_attrs("client_email", raw) do
    case ContactInfo.normalize_email(to_string(raw || "")) do
      {:ok, nil} -> %{"client_email" => nil}
      {:ok, email} -> %{"client_email" => email}
      {:error, msg} -> {:invalid, msg}
    end
  end

  defp build_inline_job_update_attrs(field, raw)
       when field in ~w(client_name address work_description customer_comments notes referred_by next_action) do
    %{field => raw |> to_string()}
  end

  defp build_inline_job_update_attrs(_, _), do: %{}

  defp inline_field_error(changeset, "phone"), do: first_changeset_error(changeset, :phone)
  defp inline_field_error(changeset, "client_email"), do: first_changeset_error(changeset, :client_email)

  defp inline_field_error(changeset, field)
       when field in ~w(client_name work_description customer_comments notes referred_by next_action priority status) do
    first_changeset_error(changeset, String.to_existing_atom(field))
  end

  defp inline_field_error(_, _), do: nil

  defp first_changeset_error(changeset, field) do
    case Keyword.get(changeset.errors, field) do
      {msg, opts} -> format_inline_error_msg(msg, opts)
      _ -> nil
    end
  end

  defp format_inline_error_msg(msg, opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

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

  defp handle_job_save_requested(socket, params, material_lines) do
    bid = socket.assigns.current_business_id

    params =
      params
      |> Map.delete("materials")
      |> Map.put("business_id", to_string(bid))

    client_id_raw = params |> Map.get("client_id", "") |> to_string() |> String.trim()

    cond do
      client_id_raw != "" ->
        case parse_id_param(client_id_raw) do
          nil ->
            finish_job_create(socket, params, material_lines, nil, nil)

          client_id ->
            params = Map.put(params, "client_id", to_string(client_id))
            finish_job_create(socket, params, material_lines, client_id, nil)
        end

      ClientContact.has_identity?(params) ->
        case MatchSuggest.suggest(bid, params) do
          {:ok, {:ambiguous, candidates}} ->
            {:noreply,
             assign(socket, :client_match, %{
               params: params,
               material_lines: material_lines,
               candidates: candidates
             })}

          _ ->
            finish_job_create(socket, params, material_lines, nil, nil)
        end

      true ->
        finish_job_create(socket, params, material_lines, nil, nil)
    end
  end

  defp finish_job_create(socket, params, material_lines, client_id, _client) do
    bid = socket.assigns.current_business_id
    uid = socket.assigns.current_scope.user.id

    params =
      if client_id do
        case Clients.get_client(client_id, bid) do
          nil ->
            params

          client ->
            params
            |> Map.merge(Clients.copy_client_contact_to_job_attrs(client))
            |> Map.put("client_id", to_string(client.id))
        end
      else
        Map.delete(params, "client_id")
      end

    case Jobs.create_job(params) do
      {:ok, job} ->
        job =
          if client_id == nil && ClientContact.has_identity?(params) do
            case Clients.create_client_from_contact_and_link_job(job, ClientContact.from_map(params)) do
              {:ok, _client, linked} -> linked
              _ -> job
            end
          else
            job
          end

        :ok = Jobs.sync_root_materials_only(job, material_lines_to_list(material_lines))
        job = Jobs.get_job!(job.id, bid)

        BusinessAuditLogs.record(%{
          business_id: bid,
          actor_user_id: uid,
          source: "web",
          action: "jobs.create",
          entity_type: "jobs",
          entity_id: job.id,
          metadata: %{client_name: job.client_name, job_id: job.id}
        })

        {:noreply,
         socket
         |> assign(:client_match, nil)
         |> refresh_jobs()
         |> push_patch(to: ~p"/")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create job. Check the form and try again.")}
    end
  end

  defp material_lines_to_list(text) do
    text
    |> to_string()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp maybe_clear_address_suggestion(socket, %{kind: :address}) do
    assign(socket, :address_suggestion, nil)
  end

  defp maybe_clear_address_suggestion(socket, _), do: socket
end
