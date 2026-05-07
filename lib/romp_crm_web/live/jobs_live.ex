defmodule RompCrmWeb.JobsLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Twilio.Phone

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket), do: Jobs.subscribe(bid)

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

    {:ok,
     socket
     |> assign(:filter, :all)
     |> assign(:expanded_job_id, nil)
     |> assign(:jobs, Jobs.list_jobs(bid))
     |> assign(:sms_intake_href, Phone.sms_uri(sms_from))
     |> assign(:sms_intake_display, Phone.format_us_display(sms_from))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
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

  def handle_info({RompCrmWeb.JobFormComponent, {:saved, _job}}, socket) do
    {:noreply, refresh_jobs(socket)}
  end

  defp refresh_jobs(socket) do
    bid = socket.assigns.current_business_id
    assign(socket, :jobs, Jobs.list_jobs(bid))
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:filter, String.to_existing_atom(status))
     |> refresh_jobs()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    bid = socket.assigns.current_business_id
    job = Jobs.get_job!(String.to_integer(id), bid)
    {:ok, _} = Jobs.delete_job(job)
    {:noreply, refresh_jobs(socket)}
  end

  def handle_event("toggle_row", %{"id" => id}, socket) do
    id = String.to_integer(id)

    expanded =
      if socket.assigns.expanded_job_id == id do
        nil
      else
        id
      end

    {:noreply,
     socket
     |> assign(:expanded_job_id, expanded)
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
end
