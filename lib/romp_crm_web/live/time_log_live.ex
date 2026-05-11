defmodule RompCrmWeb.TimeLogLive do
  use RompCrmWeb, :live_view

  alias RompCrm.TimeTracking
  alias RompCrm.TimeTracking.TimeEntry

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket), do: TimeTracking.subscribe(bid)

    {:ok,
     socket
     |> assign(:entries, TimeTracking.list_time_entries(bid))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:time_entry_created, _entry}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:time_entry_updated, _entry}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:time_entry_deleted, _entry}, socket) do
    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    assign(socket, :entries, TimeTracking.list_time_entries(socket.assigns.current_business_id))
  end

  defp format_date(%NaiveDateTime{} = dt) do
    "#{dt.month}/#{dt.day}/#{rem(dt.year, 100)}"
  end

  defp format_time(%NaiveDateTime{} = dt) do
    hour = dt.hour
    min = String.pad_leading(to_string(dt.minute), 2, "0")

    {h12, ampm} =
      if hour >= 12,
        do: {rem(hour, 12) |> then(&if &1 == 0, do: 12, else: &1), "PM"},
        else: {if(hour == 0, do: 12, else: hour), "AM"}

    "#{h12}:#{min} #{ampm}"
  end
end
