defmodule RompCrmWeb.MyTimeclockLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Employees
  alias RompCrm.Employees.TimeEntryActions
  alias RompCrmWeb.DatetimeLocal
  alias RompCrmWeb.JobTimeLogDefaults

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
     |> assign(:is_business_owner, Businesses.owner?(user, bid))
     |> assign_edit_form(nil)}
  end

  defp load_recent(nil, _bid), do: []

  defp load_recent(%{id: eid}, bid) do
    Employees.list_time_entries(eid, bid) |> Enum.take(20)
  end

  defp assign_edit_form(socket, nil) do
    socket
    |> assign(:editing_entry_id, nil)
    |> assign(:edit_clocked_in_at, "")
    |> assign(:edit_clocked_out_at, "")
    |> assign(:edit_lunch_start_at, "")
    |> assign(:edit_lunch_end_at, "")
    |> assign(:edit_notes, "")
  end

  defp assign_edit_form(socket, %Employees.EmployeeTimeEntry{} = entry) do
    socket
    |> assign(:editing_entry_id, entry.id)
    |> assign(:edit_clocked_in_at, JobTimeLogDefaults.to_datetime_local(entry.clocked_in_at))
    |> assign(:edit_clocked_out_at, datetime_local_or_blank(entry.clocked_out_at))
    |> assign(:edit_lunch_start_at, datetime_local_or_blank(entry.lunch_start_at))
    |> assign(:edit_lunch_end_at, datetime_local_or_blank(entry.lunch_end_at))
    |> assign(:edit_notes, entry.notes || "")
  end

  defp datetime_local_or_blank(nil), do: ""
  defp datetime_local_or_blank(%NaiveDateTime{} = dt), do: JobTimeLogDefaults.to_datetime_local(dt)

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
    |> assign_edit_form(nil)
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
          case TimeEntryActions.clock_in_live(bid, user.id, emp) do
            {:ok, _} ->
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
      case {socket.assigns.employee, socket.assigns.open_entry} do
        {nil, _} ->
          {:noreply, put_flash(socket, :error, "You are not on the employee roster.")}

        {_, nil} ->
          {:noreply, put_flash(socket, :error, "You are not clocked in.")}

        {emp, entry} ->
          case TimeEntryActions.clock_out_live(bid, user.id, emp, entry) do
            {:ok, _} ->
              {:noreply, refresh(socket) |> put_flash(:info, "Clocked out.")}

            {:error, cs} ->
              {:noreply, put_flash(socket, :error, format_errors(cs))}
          end
      end
    end
  end

  def handle_event("open_edit_entry", %{"id" => id}, socket) do
    if not socket.assigns.can_punch do
      {:noreply, socket}
    else
      bid = socket.assigns.current_business_id

      try do
        entry = Employees.get_time_entry!(String.to_integer(id), bid)
        emp = socket.assigns.employee

        if emp && entry.employee_id == emp.id do
          {:noreply, assign_edit_form(socket, entry)}
        else
          {:noreply, put_flash(socket, :error, "Entry not found.")}
        end
      rescue
        Ecto.NoResultsError ->
          {:noreply, put_flash(socket, :error, "Entry not found.")}
      end
    end
  end

  def handle_event("close_edit_entry", _, socket) do
    {:noreply, assign_edit_form(socket, nil)}
  end

  def handle_event("edit_field", params, socket) do
    {:noreply,
     socket
     |> assign(:edit_clocked_in_at, Map.get(params, "clocked_in_at", socket.assigns.edit_clocked_in_at))
     |> assign(:edit_clocked_out_at, Map.get(params, "clocked_out_at", socket.assigns.edit_clocked_out_at))
     |> assign(:edit_lunch_start_at, Map.get(params, "lunch_start_at", socket.assigns.edit_lunch_start_at))
     |> assign(:edit_lunch_end_at, Map.get(params, "lunch_end_at", socket.assigns.edit_lunch_end_at))
     |> assign(:edit_notes, Map.get(params, "notes", socket.assigns.edit_notes))}
  end

  def handle_event("save_edit_entry", params, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user
    emp = socket.assigns.employee
    entry_id = socket.assigns.editing_entry_id

    if is_nil(emp) or is_nil(entry_id) do
      {:noreply, socket}
    else
      with {:ok, entry} <- fetch_own_entry(entry_id, bid, emp.id),
           {:ok, attrs} <- parse_edit_attrs(params, socket),
           :ok <- validate_shift_times(attrs),
           {:ok, _} <- TimeEntryActions.adjust_entry(bid, user.id, emp, entry, attrs, via: :web) do
        {:noreply, refresh(socket) |> put_flash(:info, "Time entry updated.")}
      else
        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Entry not found.")}

        {:error, :missing_in} ->
          {:noreply, put_flash(socket, :error, "Clock-in time is required.")}

        {:error, :invalid} ->
          {:noreply, put_flash(socket, :error, "Enter valid date and time values.")}

        {:error, :end_before_start} ->
          {:noreply, put_flash(socket, :error, "Clock-out must be after clock-in.")}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, put_flash(socket, :error, format_errors(cs))}
      end
    end
  end

  def handle_event("add_manual_shift", _params, socket) do
    if socket.assigns.can_punch && socket.assigns.employee do
      {:noreply,
       socket
       |> assign(:editing_entry_id, :new)
       |> assign(:edit_clocked_in_at, "")
       |> assign(:edit_clocked_out_at, "")
       |> assign(:edit_lunch_start_at, "")
       |> assign(:edit_lunch_end_at, "")
       |> assign(:edit_notes, "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_new_shift", params, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user
    emp = socket.assigns.employee

    if is_nil(emp) do
      {:noreply, socket}
    else
      with {:ok, attrs} <- parse_edit_attrs(params, socket),
           :ok <- validate_shift_times(attrs),
           {:ok, _} <-
             TimeEntryActions.create_shift(bid, user.id, emp, attrs,
               via: :web,
               clock_in_kind: :manual_entry,
               clock_out_kind: :manual_entry
             ) do
        {:noreply, refresh(socket) |> put_flash(:info, "Shift saved.")}
      else
        {:error, :missing_in} ->
          {:noreply, put_flash(socket, :error, "Clock-in time is required.")}

        {:error, :invalid} ->
          {:noreply, put_flash(socket, :error, "Enter valid date and time values.")}

        {:error, :end_before_start} ->
          {:noreply, put_flash(socket, :error, "Clock-out must be after clock-in.")}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, put_flash(socket, :error, format_errors(cs))}
      end
    end
  end

  defp fetch_own_entry(id, bid, employee_id) do
    try do
      entry = Employees.get_time_entry!(id, bid)
      if entry.employee_id == employee_id, do: {:ok, entry}, else: {:error, :not_found}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  defp parse_edit_attrs(params, socket) do
    in_s = Map.get(params, "clocked_in_at", socket.assigns.edit_clocked_in_at)
    out_s = Map.get(params, "clocked_out_at", socket.assigns.edit_clocked_out_at)
    ls_s = Map.get(params, "lunch_start_at", socket.assigns.edit_lunch_start_at)
    le_s = Map.get(params, "lunch_end_at", socket.assigns.edit_lunch_end_at)
    notes = (Map.get(params, "notes", socket.assigns.edit_notes) || "") |> to_string() |> String.trim()

    with {:ok, clocked_in_at} <- DatetimeLocal.parse(in_s),
         {:ok, clocked_out_at} <- optional_dt(out_s),
         {:ok, lunch_start_at} <- optional_dt(ls_s),
         {:ok, lunch_end_at} <- optional_dt(le_s) do
      {:ok,
       %{
         clocked_in_at: clocked_in_at,
         clocked_out_at: clocked_out_at,
         lunch_start_at: lunch_start_at,
         lunch_end_at: lunch_end_at,
         notes: if(notes == "", do: nil, else: notes)
       }}
    else
      {:error, :missing} -> {:error, :missing_in}
      {:error, :invalid} -> {:error, :invalid}
    end
  end

  defp optional_dt(s) do
    s = s |> to_string() |> String.trim()
    if s == "", do: {:ok, nil}, else: DatetimeLocal.parse(s)
  end

  defp validate_shift_times(%{clocked_in_at: ci, clocked_out_at: co}) do
    if co && NaiveDateTime.compare(co, ci) != :gt do
      {:error, :end_before_start}
    else
      :ok
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

  def entry_kind_label(nil), do: nil
  def entry_kind_label(:live_punch), do: "Live punch"
  def entry_kind_label(:sms_punch), do: "SMS punch"
  def entry_kind_label(:manual_entry), do: "Manual entry"
  def entry_kind_label(:sms_shift), do: "Shift logged"
  def entry_kind_label(other) when is_atom(other), do: other |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
end
