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
     |> assign(:invite_forms, invite_forms_init(businesses))
     |> assign(:user, user)
     |> assign_new(:form, fn -> to_form(%{"name" => ""}, as: :business) end)
     |> assign(:page_title, "Businesses")}
  end

  defp invite_forms_init(businesses) do
    Map.new(businesses, fn b -> {b.id, empty_invite_form(b.id)} end)
  end

  defp empty_invite_form(business_id) when is_integer(business_id) do
    to_form(
      %{"email" => "", "business_id" => to_string(business_id)},
      as: :invite
    )
  end

  defp invitation_lists_for(businesses) do
    Map.new(businesses, fn b -> {b.id, Businesses.list_pending_invitations(b)} end)
  end

  defp refresh_businesses(socket) do
    businesses = Businesses.list_businesses_for_user(socket.assigns.user)
    old_forms = socket.assigns.invite_forms
    ids = MapSet.new(Enum.map(businesses, & &1.id))

    preserved =
      old_forms
      |> Enum.filter(fn {id, _} -> MapSet.member?(ids, id) end)
      |> Map.new()

    invite_forms =
      Enum.reduce(businesses, preserved, fn b, acc ->
        Map.put_new_lazy(acc, b.id, fn -> empty_invite_form(b.id) end)
      end)

    socket
    |> assign(:businesses, businesses)
    |> assign(:invitation_lists, invitation_lists_for(businesses))
    |> assign(:invite_forms, invite_forms)
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
    case Integer.parse(to_string(params["business_id"] || "")) do
      {bid, _} ->
        form = to_form(params, as: :invite)

        {:noreply, assign(socket, :invite_forms, Map.put(socket.assigns.invite_forms, bid, form))}

      :error ->
        {:noreply, socket}
    end
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
         |> then(fn s ->
           assign(s, :invite_forms, Map.put(s.assigns.invite_forms, bid, empty_invite_form(bid)))
         end)
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
