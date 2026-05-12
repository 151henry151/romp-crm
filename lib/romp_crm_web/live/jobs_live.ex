defmodule RompCrmWeb.JobsLive do
  use RompCrmWeb, :live_view

  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.TimeTracking
  alias RompCrm.TimeTracking.TimeEntry
  alias RompCrm.Twilio.Phone

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

    caps = EmployeePermissions.for(socket.assigns.current_scope.user, bid)

    {:ok,
     socket
     |> assign(:filter, :all)
     |> assign(:expanded_job_id, nil)
     |> assign(:expanded_time_entries, %{})
     |> assign(:jobs, Jobs.list_jobs(bid))
     |> assign(:can_edit_jobs, EmployeePermissions.can_edit_jobs?(caps))
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
          RompCrm.BusinessAuditLogs.record(%{
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
