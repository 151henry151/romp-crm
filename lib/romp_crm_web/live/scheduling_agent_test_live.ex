defmodule RompCrmWeb.SchedulingAgentTestLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  import RompCrmWeb.ChatComponents,
    only: [chat_thread: 1, chat_compose: 1, chat_typing_indicator: 1]

  alias RompCrm.Businesses
  alias RompCrm.SchedulingAgentTest

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, session)
    is_owner = bid && Businesses.owner?(user, bid)

    socket =
      socket
      |> assign(:page_title, "Test scheduling agent")
      |> assign(:current_business_id, bid)
      |> assign(:my_businesses, businesses)
      |> assign(:is_business_owner, is_owner == true)
      |> assign(:contractor_sending?, false)
      |> assign(:client_sending?, false)
      |> assign(:contractor_typing?, false)
      |> assign(:client_typing?, false)
      |> load_session()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("contractor_send", %{"message" => body}, socket) do
    deliver(socket, :contractor, body)
  end

  @impl true
  def handle_event("client_send", %{"message" => body}, socket) do
    deliver(socket, :client, body)
  end

  @impl true
  def handle_event("reset_test", _params, socket) do
    bid = socket.assigns.current_business_id
    user = socket.assigns.current_scope.user

    if bid do
      _ = SchedulingAgentTest.reset_session(user, bid)

      {:noreply,
       socket
       |> load_session()
       |> put_flash(:info, "Test workspace reset.")
       |> push_event("chat-scroll-bottom", %{pane: "both"})}
    else
      {:noreply, put_flash(socket, :error, "Pick a workspace first.")}
    end
  end

  @impl true
  def handle_info({:deliver, pane, body}, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    socket =
      socket
      |> assign(sending_key(pane), false)
      |> assign(typing_key(pane), false)

    socket =
      case pane do
        :contractor ->
          case SchedulingAgentTest.send_contractor(user, bid, body) do
            {:ok, _meta} ->
              load_session(socket)

            {:error, reason} ->
              socket
              |> put_flash(:error, "Could not send message. (#{inspect(reason)})")
          end

        :client ->
          case SchedulingAgentTest.send_client(user, bid, body) do
            {:ok, _reply} ->
              load_session(socket)

            {:error, :no_active_link} ->
              socket
              |> put_flash(
                :error,
                "No test customer conversation yet — start one from the contractor pane (e.g. ask the agent to reach out to schedule a visit)."
              )

            {:error, reason} ->
              socket
              |> put_flash(:error, "Could not send message. (#{inspect(reason)})")
          end
      end

    {:noreply, socket |> push_event("chat-scroll-bottom", %{pane: pane})}
  end

  defp deliver(socket, pane, body) do
    bid = socket.assigns.current_business_id
    body = body |> to_string() |> String.trim()

    cond do
      is_nil(bid) ->
        {:noreply, put_flash(socket, :error, "Pick a workspace first.")}

      body == "" ->
        {:noreply, socket}

      socket.assigns[sending_key(pane)] ->
        {:noreply, socket}

      true ->
        send(self(), {:deliver, pane, body})

        {:noreply,
         socket
         |> assign(sending_key(pane), true)
         |> assign(typing_key(pane), true)
         |> push_event("chat-scroll-bottom", %{pane: pane})}
    end
  end

  defp load_session(socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    if bid do
      state = SchedulingAgentTest.get_or_create_session(user, bid)

      socket
      |> assign(:sandbox_state, state)
      |> assign(:contractor_rows, SchedulingAgentTest.contractor_rows(state))
      |> assign(:client_rows, SchedulingAgentTest.client_rows(state))
      |> assign(:client_pane_active?, SchedulingAgentTest.client_pane_active?(state))
    else
      socket
      |> assign(:sandbox_state, nil)
      |> assign(:contractor_rows, [])
      |> assign(:client_rows, [])
      |> assign(:client_pane_active?, false)
    end
  end

  defp sending_key(:contractor), do: :contractor_sending?
  defp sending_key(:client), do: :client_sending?
  defp typing_key(:contractor), do: :contractor_typing?
  defp typing_key(:client), do: :client_typing?
end
