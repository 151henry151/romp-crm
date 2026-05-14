defmodule RompCrmWeb.MyTimeclockLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Businesses
  alias RompCrm.BusinessAuditLogs
  alias RompCrm.EmployeePermissions
  alias RompCrm.Employees

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user

    if connected?(socket), do: Employees.subscribe(bid)

    caps = EmployeePermissions.for(user, bid)
    emp = Employees.get_or_link_employee_for_user(user, bid)
    open = if emp, do: Employees.get_open_entry(emp.id, bid), else: nil

    {:ok,
     socket
     |> assign(:employee, emp)
     |> assign(:open_entry, open)
     |> assign(:recent_entries, load_recent(emp, bid))
     |> assign(:can_punch, EmployeePermissions.can_punch_own_timeclock?(caps))
     |> assign(:is_business_owner, Businesses.owner?(user, bid))}
  end

  defp load_recent(nil, _bid), do: []

  defp load_recent(%{id: eid}, bid) do
    Employees.list_time_entries(eid, bid) |> Enum.take(8)
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end

  def handle_info({:employee_time_entry_created, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:employee_time_entry_updated, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:employee_time_entry_deleted, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh(socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user
    emp = Employees.get_or_link_employee_for_user(user, bid)
    open = if emp, do: Employees.get_open_entry(emp.id, bid), else: nil

    caps = EmployeePermissions.for(user, bid)

    socket
    |> assign(:employee, emp)
    |> assign(:open_entry, open)
    |> assign(:recent_entries, load_recent(emp, bid))
    |> assign(:can_punch, EmployeePermissions.can_punch_own_timeclock?(caps))
    |> assign(:is_business_owner, Businesses.owner?(user, bid))
  end

  @impl true
  def handle_event("clock_in", _params, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user

    if not socket.assigns.can_punch do
      {:noreply, put_flash(socket, :error, "You do not have permission to use the workday timeclock.")}
    else
      emp = socket.assigns.employee

      cond do
        is_nil(emp) ->
          {:noreply, put_flash(socket, :error, "You are not linked on the employee roster for this business.")}

        socket.assigns.open_entry ->
          {:noreply, put_flash(socket, :error, "You are already clocked in. Clock out first.")}

        true ->
          at = NaiveDateTime.utc_now(:second)

          case Employees.create_time_entry(%{
                 business_id: bid,
                 employee_id: emp.id,
                 clocked_in_at: at
               }) do
            {:ok, entry} ->
              BusinessAuditLogs.record(%{
                business_id: bid,
                actor_user_id: user.id,
                source: "web",
                action: "employee_time_entries.create",
                entity_type: "employee_time_entries",
                entity_id: entry.id,
                metadata: %{kind: "clock_in", employee_id: emp.id}
              })

              {:noreply, refresh(socket) |> put_flash(:info, "Clocked in.")}

            {:error, cs} ->
              {:noreply, put_flash(socket, :error, format_errors(cs))}
          end
      end
    end
  end

  def handle_event("clock_out", _params, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user

    if not socket.assigns.can_punch do
      {:noreply, put_flash(socket, :error, "You do not have permission to use the workday timeclock.")}
    else
      case socket.assigns.open_entry do
        nil ->
          {:noreply, put_flash(socket, :error, "You are not clocked in.")}

        entry ->
          at = NaiveDateTime.utc_now(:second)

          case Employees.update_time_entry(entry, %{clocked_out_at: at}) do
            {:ok, updated} ->
              BusinessAuditLogs.record(%{
                business_id: bid,
                actor_user_id: user.id,
                source: "web",
                action: "employee_time_entries.update",
                entity_type: "employee_time_entries",
                entity_id: updated.id,
                metadata: %{kind: "clock_out", employee_id: entry.employee_id}
              })

              {:noreply, refresh(socket) |> put_flash(:info, "Clocked out.")}

            {:error, cs} ->
              {:noreply, put_flash(socket, :error, format_errors(cs))}
          end
      end
    end
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map_join("; ", fn {k, errs} -> "#{k}: #{Enum.join(errs, ", ")}" end)
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
