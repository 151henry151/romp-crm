defmodule RompCrmWeb.RemindersLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  alias RompCrm.Reminders
  alias RompCrm.Reminders.Reminder

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    prefs = Reminders.decode_prefs_json(user.sms_reminder_prefs_json)
    tz = Map.get(prefs, "timezone", "America/New_York")
    default_hour = Map.get(prefs, "send_hour_local", 9)
    businesses = socket.assigns.my_businesses
    biz_ids = Enum.map(businesses, & &1.id)
    bid = socket.assigns.current_business_id

    {:ok,
     socket
     |> assign(:page_title, "Reminders")
     |> assign(:tz, tz)
     |> assign(:default_hour, default_hour)
     |> assign(:biz_ids, biz_ids)
     |> assign(:my_businesses, businesses)
     |> assign(:is_business_owner, RompCrm.Businesses.owner?(user, bid))
     |> assign(:reminders, load_reminders(user.id, biz_ids))
     |> assign(:editing_id, nil)
     |> assign(:new_form, %{body: "", business_id: bid, date: "", time: ""})}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end

  @impl true
  def handle_event("new_reminder", params, socket) do
    user = socket.assigns.current_scope.user
    body = params |> Map.get("body", "") |> to_string() |> String.trim()
    date = params |> Map.get("date", "") |> to_string() |> String.trim()
    time = params |> Map.get("time", "") |> to_string() |> String.trim()
    bid = parse_business_id(params["business_id"], socket)

    cond do
      body == "" ->
        {:noreply, put_flash(socket, :error, "Enter reminder text.")}

      date == "" ->
        {:noreply, put_flash(socket, :error, "Pick a date.")}

      bid == nil ->
        {:noreply, put_flash(socket, :error, "Choose a business.")}

      true ->
        case Reminders.compose_fire_at_utc(date, time, socket.assigns.tz, socket.assigns.default_hour) do
          {:ok, fire_at} ->
            attrs = %{
              user_id: user.id,
              business_id: bid,
              job_id: nil,
              body: body,
              fire_at: fire_at,
              status: "pending",
              source: "web",
              metadata_json: nil
            }

            case Reminders.create_reminder(attrs) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Reminder scheduled.")
                 |> assign(:reminders, load_reminders(user.id, socket.assigns.biz_ids))
                 |> assign(:new_form, %{body: "", business_id: bid, date: "", time: ""})}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not save reminder.")}
            end

          :error ->
            {:noreply, put_flash(socket, :error, "Invalid date or time.")}
        end
    end
  end

  def handle_event("edit_start", %{"reminder_id" => id}, socket) do
    id = parse_int(id)

    if id do
      {:noreply, assign(socket, :editing_id, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_cancel", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("edit_save", params, socket) do
    user = socket.assigns.current_scope.user
    id = parse_int(params["reminder_id"])
    body = params |> Map.get("body", "") |> to_string() |> String.trim()
    date = params |> Map.get("date", "") |> to_string() |> String.trim()
    time = params |> Map.get("time", "") |> to_string() |> String.trim()

    cond do
      id == nil ->
        {:noreply, put_flash(socket, :error, "Invalid reminder.")}

      body == "" or date == "" ->
        {:noreply, put_flash(socket, :error, "Body and date are required.")}

      true ->
        case Reminders.get_user_reminder(id, user.id) do
          nil ->
            {:noreply, put_flash(socket, :error, "Reminder not found.")}

          %Reminder{} = r ->
            case Reminders.compose_fire_at_utc(date, time, socket.assigns.tz, socket.assigns.default_hour) do
              {:ok, fire_at} ->
                case Reminders.update_user_reminder(r, %{body: body, fire_at: fire_at}) do
                  {:ok, _} ->
                    {:noreply,
                     socket
                     |> put_flash(:info, "Reminder updated.")
                     |> assign(:editing_id, nil)
                     |> assign(:reminders, load_reminders(user.id, socket.assigns.biz_ids))}

                  {:error, _} ->
                    {:noreply, put_flash(socket, :error, "Could not update reminder.")}
                end

              :error ->
                {:noreply, put_flash(socket, :error, "Invalid date or time.")}
            end
        end
    end
  end

  def handle_event("delete", %{"reminder_id" => id}, socket) do
    user = socket.assigns.current_scope.user
    id = parse_int(id)

    case id && Reminders.get_user_reminder(id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Reminder not found.")}

      %Reminder{} = r ->
        case Reminders.delete_user_reminder(r) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Reminder removed.")
             |> assign(:reminders, load_reminders(user.id, socket.assigns.biz_ids))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete reminder.")}
        end
    end
  end

  defp load_reminders(user_id, biz_ids), do: Reminders.list_pending_reminders_for_user(user_id, biz_ids)

  defp parse_business_id(raw, socket) do
    case parse_int(to_string(raw || "")) do
      nil ->
        nil

      id ->
        if id in socket.assigns.biz_ids, do: id, else: nil
    end
  end

  defp parse_int(v) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  def fire_at_date_part(%DateTime{} = utc, tz) do
    case DateTime.shift_zone(utc, tz) do
      {:ok, local} ->
        y = local.year
        mo = local.month |> Integer.to_string() |> String.pad_leading(2, "0")
        d = local.day |> Integer.to_string() |> String.pad_leading(2, "0")
        "#{y}-#{mo}-#{d}"

      _ ->
        ""
    end
  end

  def fire_at_time_part(%DateTime{} = utc, tz) do
    case DateTime.shift_zone(utc, tz) do
      {:ok, local} ->
        h = local.hour |> Integer.to_string() |> String.pad_leading(2, "0")
        m = local.minute |> Integer.to_string() |> String.pad_leading(2, "0")
        h <> ":" <> m

      _ ->
        ""
    end
  end

  def business_name(businesses, bid) do
    case Enum.find(businesses, &(&1.id == bid)) do
      %{name: n} when is_binary(n) -> n
      _ -> "Business ##{bid}"
    end
  end
end
