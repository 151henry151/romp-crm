defmodule RompCrmWeb.ClientsLive do
  use RompCrmWeb, :live_view

  import RompCrmWeb.ClientExpandedInlineFields
  import RompCrmWeb.ClientDeleteBar, only: [client_delete_bar: 1]

  alias RompCrm.Businesses
  alias RompCrm.Clients
  alias RompCrm.Clients.Client
  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs
  alias RompCrmWeb.AddressFormHandlers
  alias RompCrmWeb.ClientExpandEditKeys, as: CEK
  alias RompCrmWeb.ClientsList
  alias RompCrmWeb.JobsList
  alias RompCrm.ContactInfo

  @impl true
  def mount(_params, _session, socket) do
    bid = socket.assigns.current_business_id

    if connected?(socket) do
      Clients.subscribe(bid)
      Jobs.subscribe(bid)
    end

    user = socket.assigns.current_scope.user
    caps = EmployeePermissions.for(user, bid)

    {:ok,
     socket
     |> assign(:sort_by, :name)
     |> assign(:expanded_client_id, nil)
     |> assign(:client_expand_editing, MapSet.new())
     |> assign(:client_delete_steps, %{})
     |> assign(:address_suggestion, nil)
     |> assign(:clients, Clients.list_clients(bid))
     |> assign(:can_edit_jobs, EmployeePermissions.can_edit_jobs?(caps))
     |> assign(:is_business_owner, Businesses.owner?(user, bid))}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:created, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:updated, _}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:deleted, _}, socket), do: {:noreply, refresh(socket)}

  @impl true
  def handle_event("set_sort", %{"sort" => sort}, socket) do
    sort_by = parse_sort(sort)
    {:noreply, assign(socket, :sort_by, sort_by)}
  end

  def handle_event("toggle_row", %{"id" => id}, socket) do
    cid = parse_id(id)
    expanded = socket.assigns.expanded_client_id

    {:noreply,
     socket
     |> assign(:expanded_client_id, if(expanded == cid, do: nil, else: cid))
     |> assign(:client_expand_editing, MapSet.new())
     |> assign(:address_suggestion, nil)}
  end

  def handle_event("client_expand_edit_start", %{"key" => key}, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, socket}
    else
      keys = MapSet.put(socket.assigns.client_expand_editing, key)
      {:noreply, assign(socket, :client_expand_editing, keys)}
    end
  end

  def handle_event("client_expand_edit_cancel", %{"key" => key}, socket) do
    keys = MapSet.delete(socket.assigns.client_expand_editing, key)

    {:noreply,
     socket
     |> assign(:client_expand_editing, keys)
     |> assign(:address_suggestion, nil)}
  end

  def handle_event("client_expand_commit", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit clients.")}
    else
      commit_client_field(socket, params)
    end
  end

  def handle_event("client_expand_commit_address", params, socket) do
    if not socket.assigns.can_edit_jobs do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit clients.")}
    else
      client_id = parse_id(params["client_id"])
      attrs = AddressFormHandlers.client_address_attrs_from_params(params)
      edit_key = CEK.client(client_id, "address")
      save_client_attrs(socket, client_id, attrs, edit_key)
    end
  end

  def handle_event("address_validate", params, socket) do
    {:noreply, assign(socket, :address_suggestion, AddressFormHandlers.build_suggestion(params))}
  end

  def handle_event("client_delete_advance", %{"id" => id}, socket) do
    cid = parse_id(id)
    steps = socket.assigns.client_delete_steps
    step = Map.get(steps, cid, 0)

    if step >= 2 and cid do
      case Clients.get_client(cid, socket.assigns.current_business_id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Client not found.")}

        client ->
          case Clients.delete_client_and_jobs(client) do
            {:ok, _} ->
              {:noreply,
               socket
               |> refresh()
               |> assign(:expanded_client_id, nil)
               |> assign(:client_delete_steps, Map.delete(steps, cid))
               |> put_flash(:info, "Client and linked jobs deleted.")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not delete client.")}
          end
      end
    else
      {:noreply, assign(socket, :client_delete_steps, Map.put(steps, cid, step + 1))}
    end
  end

  def handle_event("client_delete_cancel", %{"id" => id}, socket) do
    cid = parse_id(id)
    {:noreply, assign(socket, :client_delete_steps, Map.delete(socket.assigns.client_delete_steps, cid))}
  end

  defp commit_client_field(socket, %{"client_id" => cid, "field" => field} = params) do
    client_id = parse_id(cid)
    field = to_string(field || "")
    raw = Map.get(params, "value")
    edit_key = CEK.client(client_id, field)

    attrs =
      cond do
        field == "phone" ->
          case ContactInfo.normalize_phone(to_string(raw || "")) do
            {:ok, nil} -> %{"phone" => nil}
            {:ok, phone} -> %{"phone" => phone}
            {:error, msg} -> {:invalid, msg}
          end

        field == "client_email" ->
          case ContactInfo.normalize_email(to_string(raw || "")) do
            {:ok, nil} -> %{"client_email" => nil}
            {:ok, email} -> %{"client_email" => email}
            {:error, msg} -> {:invalid, msg}
          end

        field in ~w(client_name notes) ->
          %{field => to_string(raw || "")}

        true ->
          %{}
      end

    case attrs do
      {:invalid, msg} ->
        {:noreply, put_flash(socket, :error, msg)}

      map when map == %{} ->
        {:noreply, drop_edit(socket, edit_key)}

      map ->
        save_client_attrs(socket, client_id, map, edit_key)
    end
  end

  defp commit_client_field(socket, _), do: {:noreply, put_flash(socket, :error, "Invalid request.")}

  defp save_client_attrs(socket, client_id, attrs, edit_key) when is_map(attrs) do
    bid = socket.assigns.current_business_id

    case Clients.get_client(client_id, bid) do
      nil ->
        {:noreply, put_flash(socket, :error, "Client not found.")}

      client ->
        case Clients.update_client_and_sync_jobs(client, attrs) do
          {:ok, _} ->
            {:noreply, socket |> refresh() |> drop_edit(edit_key) |> assign(:address_suggestion, nil)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not save that change.")}
        end
    end
  end

  defp refresh(socket) do
    bid = socket.assigns.current_business_id
    assign(socket, :clients, Clients.list_clients(bid))
  end

  defp drop_edit(socket, key) do
    assign(socket, :client_expand_editing, MapSet.delete(socket.assigns.client_expand_editing, key))
  end

  defp parse_id(v) do
    case Integer.parse(to_string(v || "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_sort("updated"), do: :updated
  defp parse_sort("address"), do: :address
  defp parse_sort(_), do: :name

  defp expanded?(expanded_id, id), do: expanded_id == id
end
