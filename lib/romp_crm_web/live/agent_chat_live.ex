defmodule RompCrmWeb.AgentChatLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  import RompCrmWeb.ChatComponents, only: [chat_thread: 1, chat_compose: 1]

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

    {:ok, load_thread(socket)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("chat_send", %{"message" => body}, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    cond do
      is_nil(bid) ->
        {:noreply, put_flash(socket, :error, "Pick a workspace first.")}

      socket.assigns.chat_sending? ->
        {:noreply, socket}

      true ->
        socket = assign(socket, :chat_sending?, true)

        case AgentChat.send_message(user, bid, body || "") do
          {:ok, _reply} ->
            {:noreply,
             socket
             |> assign(:chat_sending?, false)
             |> load_thread()
             |> push_event("chat-scroll-bottom", %{})}

          {:error, :empty} ->
            {:noreply, assign(socket, :chat_sending?, false)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:chat_sending?, false)
             |> put_flash(:error, "Could not send message. (#{inspect(reason)})")}
        end
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
end
