defmodule RompCrmWeb.AgentChatLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  import RompCrmWeb.ChatComponents, only: [chat_thread: 1, chat_compose: 1, chat_typing_indicator: 1]

  alias RompCrm.AgentChat
  alias RompCrm.Businesses
  alias RompCrm.Conversations

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, session)
    is_owner = bid && Businesses.owner?(user, bid)

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:current_business_id, bid)
      |> assign(:my_businesses, businesses)
      |> assign(:is_business_owner, is_owner == true)
      |> assign(:chat_rows, [])
      |> assign(:chat_sending?, false)
      |> assign(:chat_agent_typing?, false)

    {:ok, load_thread(socket)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("chat_send", %{"message" => body}, socket) do
    bid = socket.assigns.current_business_id
    body = body |> to_string() |> String.trim()

    cond do
      is_nil(bid) ->
        {:noreply, put_flash(socket, :error, "Pick a workspace first.")}

      body == "" ->
        {:noreply, socket}

      socket.assigns.chat_sending? ->
        {:noreply, socket}

      true ->
        send(self(), {:chat_deliver, body})

        {:noreply,
         socket
         |> assign(:chat_sending?, true)
         |> assign(:chat_agent_typing?, true)
         |> update(:chat_rows, &(&1 ++ [optimistic_self_row(body)]))
         |> push_event("chat-scroll-bottom", %{})}
    end
  end

  @impl true
  def handle_info({:chat_deliver, body}, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    result = AgentChat.send_message(user, bid, body)

    socket =
      socket
      |> assign(:chat_sending?, false)
      |> assign(:chat_agent_typing?, false)

    case result do
      {:ok, _reply} ->
        {:noreply,
         socket
         |> load_thread()
         |> push_event("chat-scroll-bottom", %{})}

      {:error, :empty} ->
        {:noreply, drop_pending_rows(socket)}

      {:error, reason} ->
        {:noreply,
         socket
         |> drop_pending_rows()
         |> put_flash(:error, "Could not send message. (#{inspect(reason)})")}
    end
  end

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end

  defp load_thread(socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    rows =
      if bid do
        :agent
        |> Conversations.list_thread_messages(bid)
        |> Conversations.format_thread_rows(user, bid)
      else
        []
      end

    assign(socket, :chat_rows, rows)
  end

  defp optimistic_self_row(body) do
    %{
      id: "pending-#{System.unique_integer([:positive])}",
      label: "You",
      role: :self,
      side: :right,
      text: body,
      photos: [],
      inserted_at: DateTime.utc_now(),
      channel: "in_app",
      pending: true
    }
  end

  defp drop_pending_rows(socket) do
    update(socket, :chat_rows, fn rows ->
      Enum.reject(rows, &Map.get(&1, :pending))
    end)
  end
end
