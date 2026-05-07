defmodule RompCrmWeb.BusinessesLive do
  use RompCrmWeb, :live_view

  alias RompCrm.Businesses

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)

    {:ok,
     socket
     |> assign(:businesses, businesses)
     |> assign(:invitation_lists, invitation_lists_for(businesses))
     |> assign(:user, user)
     |> assign_new(:form, fn -> to_form(%{"name" => ""}, as: :business) end)
     |> assign_new(:invite_form, fn -> to_form(%{"email" => ""}, as: :invite) end)
     |> assign(:page_title, "Businesses")}
  end

  defp invitation_lists_for(businesses) do
    Map.new(businesses, fn b -> {b.id, Businesses.list_pending_invitations(b)} end)
  end

  defp refresh_businesses(socket) do
    businesses = Businesses.list_businesses_for_user(socket.assigns.user)

    socket
    |> assign(:businesses, businesses)
    |> assign(:invitation_lists, invitation_lists_for(businesses))
  end

  @impl true
  def handle_event("validate_business", %{"business" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :business))}
  end

  def handle_event("create_business", %{"business" => %{"name" => name}}, socket) do
    name = String.trim(to_string(name))

    case Businesses.create_business(socket.assigns.user, %{name: name}) do
      {:ok, business} ->
        {:noreply,
         socket
         |> refresh_businesses()
         |> assign(:form, to_form(%{"name" => ""}, as: :business))
         |> put_flash(:info, "Created #{business.name}.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :business))}
    end
  end

  def handle_event("validate_invite", %{"invite" => params}, socket) do
    {:noreply, assign(socket, :invite_form, to_form(params, as: :invite))}
  end

  def handle_event(
        "invite",
        %{"invite" => %{"email" => email, "business_id" => bid}},
        socket
      ) do
    bid = String.to_integer(to_string(bid))
    business = Businesses.get_business!(bid)

    case Businesses.invite_user(business, socket.assigns.user, email) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh_businesses()
         |> assign(:invite_form, to_form(%{"email" => ""}, as: :invite))
         |> put_flash(:info, "Invitation sent.")}

      {:error, :not_owner} ->
        {:noreply, put_flash(socket, :error, "Only a business owner can invite users.")}

      {:error, :already_member} ->
        {:noreply, put_flash(socket, :error, "That user is already a member.")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not create invitation (duplicate invite?).")}
    end
  end

  def handle_event("cancel_invite", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Businesses.cancel_invitation(socket.assigns.user, id) do
      {:ok, _} ->
        {:noreply, socket |> refresh_businesses() |> put_flash(:info, "Invitation removed.")}

      {:error, :not_owner} ->
        {:noreply, put_flash(socket, :error, "Not allowed.")}
    end
  end
end
