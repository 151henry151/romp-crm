defmodule RompCrmWeb.ChatsLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  import RompCrmWeb.ChatComponents,
    only: [chat_thread: 1, chat_compose: 1, chat_typing_indicator: 1]

  alias RompCrm.AgentChat
  alias RompCrm.Businesses
  alias RompCrm.ClientChats
  alias RompCrm.Conversations

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, session)
    is_owner = bid && Businesses.owner?(user, bid)

    socket =
      socket
      |> assign(:page_title, "Chats")
      |> assign(:current_business_id, bid)
      |> assign(:my_businesses, businesses)
      |> assign(:is_business_owner, is_owner == true)
      |> assign(:thread_kind, :agent)
      |> assign(:client_phone, nil)
      |> assign(:client_name, nil)
      |> assign(:chat_rows, [])
      |> assign(:thread_list, [])
      |> assign(:chat_sending?, false)
      |> assign(:chat_agent_typing?, false)
      |> assign(:client_taken_over?, false)
      |> assign(:show_takeover_confirm?, false)
      |> assign(:pending_chat_photos, [])
      |> assign(:mobile_view, :list)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_thread_params(params)
      |> load_sidebar()
      |> load_active_thread()
      |> subscribe_client_thread()

    {:noreply, socket}
  end

  @impl true
  def handle_event("chat_send", %{"message" => body}, socket) do
    case socket.assigns.thread_kind do
      :agent -> deliver_agent(socket, body)
      :client -> deliver_client(socket, body)
    end
  end

  @impl true
  def handle_event("chat_media_uploaded", %{"url" => url}, socket) do
    url = url |> to_string() |> String.trim()

    cond do
      url == "" ->
        {:noreply, socket}

      length(socket.assigns.pending_chat_photos) >= RompCrm.ChatMedia.max_images() ->
        {:noreply, put_flash(socket, :error, "You can attach up to #{RompCrm.ChatMedia.max_images()} photos.")}

      true ->
        {:noreply, update(socket, :pending_chat_photos, &(&1 ++ [url]))}
    end
  end

  @impl true
  def handle_event("chat_remove_pending_photo", %{"index" => idx}, socket) do
    case Integer.parse(to_string(idx)) do
      {i, _} ->
        photos = List.delete_at(socket.assigns.pending_chat_photos, i)
        {:noreply, assign(socket, :pending_chat_photos, photos)}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_takeover_confirm", _params, socket) do
    {:noreply, assign(socket, :show_takeover_confirm?, true)}
  end

  @impl true
  def handle_event("cancel_takeover_confirm", _params, socket) do
    {:noreply, assign(socket, :show_takeover_confirm?, false)}
  end

  @impl true
  def handle_event("confirm_takeover", _params, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id
    phone = socket.assigns.client_phone

    socket = assign(socket, :show_takeover_confirm?, false)

    case ClientChats.take_over!(user, bid, phone) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "You took over this chat. The customer was notified by text.")
         |> load_active_thread()
         |> push_event("chat-scroll-bottom", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not take over chat. (#{inspect(reason)})")}
    end
  end

  @impl true
  def handle_event("hand_off", _params, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id
    phone = socket.assigns.client_phone

    case ClientChats.hand_off!(user, bid, phone) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Handed chat back to the scheduling agent. The customer was notified.")
         |> load_active_thread()
         |> push_event("chat-scroll-bottom", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not hand off chat. (#{inspect(reason)})")}
    end
  end

  @impl true
  def handle_info({:chat_deliver, body, media_urls}, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    result = AgentChat.send_message(user, bid, body, media_urls: media_urls)

    socket =
      socket
      |> assign(:chat_sending?, false)
      |> assign(:chat_agent_typing?, false)

    case result do
      {:ok, _reply} ->
        {:noreply,
         socket
         |> assign(:pending_chat_photos, [])
         |> load_active_thread()
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
  def handle_info({:client_deliver, body, media_urls}, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id
    phone = socket.assigns.client_phone

    socket = assign(socket, :chat_sending?, false)

    case ClientChats.send_human_message!(user, bid, phone, body, media_urls: media_urls) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:pending_chat_photos, [])
         |> load_active_thread()
         |> push_event("chat-scroll-bottom", %{})}

      {:error, :not_taken_over} ->
        {:noreply, put_flash(socket, :error, "Take over the chat before replying as a live person.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not send SMS. (#{inspect(reason)})")}
    end
  end

  @impl true
  def handle_info({:message, _bid, phone}, socket) do
    if socket.assigns.thread_kind == :client and socket.assigns.client_phone == phone do
      {:noreply, load_active_thread(socket)}
    else
      {:noreply, load_sidebar(socket)}
    end
  end

  @impl true
  def handle_info({:takeover, _bid, phone}, socket) do
    if socket.assigns.thread_kind == :client and socket.assigns.client_phone == phone do
      {:noreply, load_active_thread(socket)}
    else
      {:noreply, load_sidebar(socket)}
    end
  end

  @impl true
  def handle_info({:handoff, _bid, phone}, socket) do
    if socket.assigns.thread_kind == :client and socket.assigns.client_phone == phone do
      {:noreply, load_active_thread(socket)}
    else
      {:noreply, load_sidebar(socket)}
    end
  end

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end

  def active_thread?(thread, kind, phone) do
    case thread.kind do
      :agent -> kind == :agent and is_nil(phone)
      :client -> kind == :client and thread.phone_normalized == phone
    end
  end

  def thread_patch(thread) do
    case thread.kind do
      :agent -> ~p"/chats?thread=agent"
      :client -> ~p"/chats?phone=#{thread.phone_normalized}"
    end
  end

  def compose_placeholder(:agent, _), do: "Message the RompCRM agent…"

  def compose_placeholder(:client, true), do: "Reply to the customer by SMS…"

  def compose_placeholder(:client, false),
    do: "Take over the chat to send a live reply…"

  def compose_disabled?(:client, false, _), do: true
  def compose_disabled?(_kind, _taken_over, sending?), do: sending?

  def chat_media_upload_url(:agent, _, _), do: ~p"/chats/media"

  def chat_media_upload_url(:client, true, phone) when is_binary(phone) and phone != "" do
    ~p"/chats/media?#{[phone: phone]}"
  end

  def chat_media_upload_url(_, _, _), do: nil

  def compose_attach_enabled?(:agent, _), do: true
  def compose_attach_enabled?(:client, true), do: true
  def compose_attach_enabled?(_, _), do: false

  defp deliver_agent(socket, body) do
    bid = socket.assigns.current_business_id
    body = body |> to_string() |> String.trim()
    media_urls = socket.assigns.pending_chat_photos || []

    cond do
      is_nil(bid) ->
        {:noreply, put_flash(socket, :error, "Pick a workspace first.")}

      body == "" and media_urls == [] ->
        {:noreply, socket}

      socket.assigns.chat_sending? ->
        {:noreply, socket}

      true ->
        send(self(), {:chat_deliver, body, media_urls})

        {:noreply,
         socket
         |> assign(:chat_sending?, true)
         |> assign(:chat_agent_typing?, true)
         |> update(:chat_rows, &(&1 ++ [optimistic_self_row(body, media_urls)]))
         |> push_event("chat-scroll-bottom", %{})}
    end
  end

  defp deliver_client(socket, body) do
    bid = socket.assigns.current_business_id
    phone = socket.assigns.client_phone
    body = body |> to_string() |> String.trim()
    media_urls = socket.assigns.pending_chat_photos || []

    cond do
      is_nil(bid) or is_nil(phone) ->
        {:noreply, put_flash(socket, :error, "Pick a client conversation first.")}

      not socket.assigns.client_taken_over? ->
        {:noreply, put_flash(socket, :error, "Take over the chat before sending a live reply.")}

      body == "" and media_urls == [] ->
        {:noreply, socket}

      socket.assigns.chat_sending? ->
        {:noreply, socket}

      true ->
        send(self(), {:client_deliver, body, media_urls})

        {:noreply,
         socket
         |> assign(:chat_sending?, true)
         |> update(:chat_rows, &(&1 ++ [optimistic_human_row(body, media_urls)]))
         |> push_event("chat-scroll-bottom", %{})}
    end
  end

  defp apply_thread_params(socket, params) do
    mobile_view = mobile_view_from_params(params)
    prev_phone = socket.assigns[:client_phone]
    prev_kind = socket.assigns[:thread_kind]

    socket =
      case client_phone_param(params) do
        phone when is_binary(phone) ->
          socket
          |> assign(:thread_kind, :client)
          |> assign(:client_phone, phone)

        :agent_thread ->
          socket
          |> assign(:thread_kind, :agent)
          |> assign(:client_phone, nil)
          |> assign(:client_name, nil)

        :default ->
          socket
          |> assign(:thread_kind, :agent)
          |> assign(:client_phone, nil)
          |> assign(:client_name, nil)
      end

    socket =
      if socket.assigns.thread_kind != prev_kind or socket.assigns.client_phone != prev_phone do
        assign(socket, :pending_chat_photos, [])
      else
        socket
      end

    assign(socket, :mobile_view, mobile_view)
  end

  defp client_phone_param(%{"phone" => phone}) when is_binary(phone) do
    phone = String.trim(phone)
    if phone != "", do: phone, else: :default
  end

  defp client_phone_param(%{"thread" => "agent"}), do: :agent_thread
  defp client_phone_param(_), do: :default

  defp mobile_view_from_params(params) do
    case client_phone_param(params) do
      phone when is_binary(phone) -> :thread
      :agent_thread -> :thread
      :default -> :list
    end
  end

  defp load_sidebar(socket) do
    bid = socket.assigns.current_business_id

    threads =
      if bid do
        agent = %{
          id: "agent",
          kind: :agent,
          label: "RompCRM agent",
          subtitle: "Your assistant",
          phone_normalized: nil,
          taken_over?: false
        }

        clients = ClientChats.list_thread_summaries(bid)

        client_items =
          Enum.map(clients, fn c ->
            %{
              id: c.id,
              kind: :client,
              label: c.client_name,
              subtitle: client_subtitle(c),
              phone_normalized: c.phone_normalized,
              taken_over?: c.taken_over?
            }
          end)

        [agent | client_items]
      else
        []
      end

    name =
      case Enum.find(threads, fn t ->
             t.kind == :client and t.phone_normalized == socket.assigns.client_phone
           end) do
        %{label: n} -> n
        _ -> socket.assigns.client_name
      end

    assign(socket, thread_list: threads, client_name: name)
  end

  defp client_subtitle(c) do
    parts =
      []
      |> then(fn p -> if c.job_type_label not in [nil, ""], do: [c.job_type_label | p], else: p end)
      |> then(fn p -> if c.taken_over?, do: ["Live chat" | p], else: p end)

    case parts do
      [] -> "Scheduling SMS"
      [one] -> one
      list -> Enum.join(list, " · ")
    end
  end

  defp load_active_thread(socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    socket =
      case {bid, socket.assigns.thread_kind, socket.assigns.client_phone} do
        {bid, :agent, _} when is_integer(bid) ->
          rows =
            :agent
            |> Conversations.list_thread_messages(bid)
            |> Conversations.format_thread_rows(user, bid)

          socket
          |> assign(:chat_rows, rows)
          |> assign(:client_taken_over?, false)

        {bid, :client, phone} when is_integer(bid) and is_binary(phone) ->
          name = socket.assigns.client_name || "Customer"

          rows =
            :client
            |> Conversations.list_thread_messages(bid, phone)
            |> Conversations.format_client_thread_rows(name)

          socket
          |> assign(:chat_rows, rows)
          |> assign(:client_taken_over?, ClientChats.taken_over?(bid, phone))

        _ ->
          assign(socket, chat_rows: [], client_taken_over?: false)
      end

    load_sidebar(socket)
  end

  defp subscribe_client_thread(socket) do
    if connected?(socket) and socket.assigns.thread_kind == :client and
         socket.assigns.client_phone &&
         socket.assigns.current_business_id do
      Phoenix.PubSub.subscribe(
        RompCrm.PubSub,
        ClientChats.pubsub_topic(socket.assigns.current_business_id, socket.assigns.client_phone)
      )
    end

    socket
  end

  defp optimistic_self_row(body, media_urls) do
    %{
      id: "pending-#{System.unique_integer([:positive])}",
      label: "You",
      role: :self,
      side: :right,
      text: if(body == "", do: nil, else: body),
      photos: media_urls,
      inserted_at: DateTime.utc_now(),
      channel: "in_app",
      pending: true
    }
  end

  defp optimistic_human_row(body, media_urls) do
    %{
      id: "pending-#{System.unique_integer([:positive])}",
      label: "You (live)",
      role: :self,
      side: :right,
      text: if(body == "", do: nil, else: body),
      photos: media_urls,
      inserted_at: DateTime.utc_now(),
      channel: "sms_human",
      pending: true
    }
  end

  defp drop_pending_rows(socket) do
    update(socket, :chat_rows, fn rows ->
      Enum.reject(rows, &Map.get(&1, :pending))
    end)
  end
end
