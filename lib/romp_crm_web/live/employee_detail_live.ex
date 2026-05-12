defmodule RompCrmWeb.EmployeeDetailLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Businesses
  alias RompCrm.Employees
  alias RompCrm.Employees.EmployeeTimeEntry

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bid = socket.assigns.current_business_id
    emp = Employees.get_employee!(String.to_integer(id), bid)

    if connected?(socket), do: Employees.subscribe(bid)

    {:ok,
     socket
     |> assign(:employee, emp)
     |> assign(:entries, Employees.list_time_entries(emp.id, bid))
     |> assign(:my_businesses, Businesses.list_businesses_for_user(socket.assigns.current_scope.user))
     |> assign(:is_business_owner, true)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:employee_time_entry_created, _entry}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:employee_time_entry_updated, _entry}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({:employee_time_entry_deleted, _entry}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh(socket) do
    bid = socket.assigns.current_business_id
    emp = socket.assigns.employee
    assign(socket, :entries, Employees.list_time_entries(emp.id, bid))
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

  defp total_label(entries) do
    total =
      Enum.reduce(entries, 0, fn e, acc ->
        case EmployeeTimeEntry.worked_minutes(e) do
          nil -> acc
          m -> acc + m
        end
      end)

    h = div(total, 60)
    m = rem(total, 60)

    cond do
      h == 0 and m == 0 -> "0m total"
      h == 0 -> "#{m}m total"
      m == 0 -> "#{h}h total"
      true -> "#{h}h #{m}m total"
    end
  end
end
