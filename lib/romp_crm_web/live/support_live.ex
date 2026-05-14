defmodule RompCrmWeb.SupportLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  alias RompCrm.Businesses

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, session)
    is_owner = bid && Businesses.owner?(user, bid)

    {:ok,
     socket
     |> assign(:page_title, "Support")
     |> assign(:current_business_id, bid)
     |> assign(:my_businesses, businesses)
     |> assign(:is_business_owner, is_owner == true)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end
end
