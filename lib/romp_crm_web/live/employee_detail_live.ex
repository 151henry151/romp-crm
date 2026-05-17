defmodule RompCrmWeb.EmployeeDetailLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Employees
  alias RompCrm.Employees.{EmployeeTimeEntry, TimeEntryActions}
  alias RompCrmWeb.DatetimeLocal
  alias RompCrmWeb.JobTimeLogDefaults

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user
    emp = Employees.get_employee!(String.to_integer(id), bid)

    if connected?(socket), do: Employees.subscribe(bid)

    caps = EmployeePermissions.for(user, bid)

    {:ok,
     socket
     |> assign(:employee, emp)
     |> assign(:entries, Employees.list_time_entries(emp.id, bid))
     |> assign(:my_businesses, Businesses.list_businesses_for_user(user))
     |> assign(:is_business_owner, true)
     |> assign(:can_manage_time, EmployeePermissions.can_log_employee_time?(caps, emp.id))
     |> assign_edit_form(nil)}
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

  defp assign_edit_form(socket, %EmployeeTimeEntry{} = entry) do
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

  def handle_info({:employee_time_entry_created, _entry}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:employee_time_entry_updated, _entry}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:employee_time_entry_deleted, _entry}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh(socket) do
    bid = socket.assigns.current_business_id
    emp = socket.assigns.employee

    socket
    |> assign(:entries, Employees.list_time_entries(emp.id, bid))
    |> assign_edit_form(nil)
  end

  @impl true
  def handle_event("open_edit_entry", %{"id" => id}, socket) do
    if socket.assigns.can_manage_time do
      bid = socket.assigns.current_business_id

      try do
        entry = Employees.get_time_entry!(String.to_integer(id), bid)

        if entry.employee_id == socket.assigns.employee.id do
          {:noreply, assign_edit_form(socket, entry)}
        else
          {:noreply, put_flash(socket, :error, "Entry not found.")}
        end
      rescue
        Ecto.NoResultsError -> {:noreply, put_flash(socket, :error, "Entry not found.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_edit_entry", _, socket), do: {:noreply, assign_edit_form(socket, nil)}

  def handle_event("add_manual_shift", _, socket) do
    if socket.assigns.can_manage_time do
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

  def handle_event("edit_field", params, socket) do
    {:noreply,
     socket
     |> assign(:edit_clocked_in_at, Map.get(params, "clocked_in_at", socket.assigns.edit_clocked_in_at))
     |> assign(:edit_clocked_out_at, Map.get(params, "clocked_out_at", socket.assigns.edit_clocked_out_at))
     |> assign(:edit_lunch_start_at, Map.get(params, "lunch_start_at", socket.assigns.edit_lunch_start_at))
     |> assign(:edit_lunch_end_at, Map.get(params, "lunch_end_at", socket.assigns.edit_lunch_end_at))
     |> assign(:edit_notes, Map.get(params, "notes", socket.assigns.edit_notes))}
  end

  def handle_event("save_edit_entry", params, socket), do: save_entry(socket, params, :edit)
  def handle_event("save_new_shift", params, socket), do: save_entry(socket, params, :new)

  def handle_event("delete_entry", %{"id" => id}, socket) do
    if socket.assigns.can_manage_time do
      bid = socket.assigns.current_business_id
      user = socket.assigns.current_scope.user
      emp = socket.assigns.employee

      try do
        entry = Employees.get_time_entry!(String.to_integer(id), bid)

        if entry.employee_id == emp.id do
          case TimeEntryActions.delete_entry(bid, user.id, emp, entry) do
            {:ok, _} -> {:noreply, refresh(socket) |> put_flash(:info, "Entry deleted.")}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete entry.")}
          end
        else
          {:noreply, put_flash(socket, :error, "Entry not found.")}
        end
      rescue
        Ecto.NoResultsError -> {:noreply, put_flash(socket, :error, "Entry not found.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp save_entry(socket, params, mode) do
    if not socket.assigns.can_manage_time do
      {:noreply, socket}
    else
      bid = socket.assigns.current_business_id
      user = socket.assigns.current_scope.user
      emp = socket.assigns.employee
      entry_id = socket.assigns.editing_entry_id

      with {:ok, attrs} <- parse_edit_attrs(params, socket),
           :ok <- validate_shift_times(attrs),
           {:ok, _} <- apply_save(mode, bid, user, emp, entry_id, attrs) do
        msg = if mode == :new, do: "Shift saved.", else: "Time entry updated."
        {:noreply, refresh(socket) |> put_flash(:info, msg)}
      else
        {:error, :missing_in} -> {:noreply, put_flash(socket, :error, "Clock-in time is required.")}
        {:error, :invalid} -> {:noreply, put_flash(socket, :error, "Enter valid date and time values.")}
        {:error, :end_before_start} -> {:noreply, put_flash(socket, :error, "Clock-out must be after clock-in.")}
        {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Entry not found.")}
        {:error, %Ecto.Changeset{} = cs} -> {:noreply, put_flash(socket, :error, format_errors(cs))}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not save.")}
      end
    end
  end

  defp apply_save(:new, bid, user, emp, _, attrs) do
    TimeEntryActions.create_shift(bid, user.id, emp, attrs,
      via: :web,
      clock_in_kind: :manual_entry,
      clock_out_kind: :manual_entry
    )
  end

  defp apply_save(:edit, bid, user, emp, entry_id, attrs) when is_integer(entry_id) do
    try do
      entry = Employees.get_time_entry!(entry_id, bid)

      if entry.employee_id == emp.id do
        TimeEntryActions.adjust_entry(bid, user.id, emp, entry, attrs, via: :web)
      else
        {:error, :not_found}
      end
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  defp apply_save(:edit, _, _, _, _, _), do: {:error, :not_found}

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
    if co && NaiveDateTime.compare(co, ci) != :gt, do: {:error, :end_before_start}, else: :ok
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map_join("; ", fn {k, errs} -> "#{k}: #{Enum.join(errs, ", ")}" end)
  end

  defp format_date(%NaiveDateTime{} = dt), do: "#{dt.month}/#{dt.day}/#{rem(dt.year, 100)}"

  defp format_time(%NaiveDateTime{} = dt) do
    hour = dt.hour
    min = String.pad_leading(to_string(dt.minute), 2, "0")
    {h12, ampm} = if hour >= 12, do: {rem(hour, 12) |> then(&if &1 == 0, do: 12, else: &1), "PM"}, else: {if(hour == 0, do: 12, else: hour), "AM"}
    "#{h12}:#{min} #{ampm}"
  end

  def entry_kind_label(nil), do: "—"
  def entry_kind_label(:live_punch), do: "Live punch"
  def entry_kind_label(:sms_punch), do: "SMS punch"
  def entry_kind_label(:manual_entry), do: "Manual"
  def entry_kind_label(:sms_shift), do: "Shift logged"
  def entry_kind_label(k) when is_atom(k), do: k |> Atom.to_string() |> String.replace("_", " ")

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
