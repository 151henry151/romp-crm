defmodule RompCrmWeb.AdminLive do
  @moduledoc false
  use RompCrmWeb, :live_view

  alias RompCrm.Admin
  alias RompCrm.Businesses
  alias RompCrm.Gifts

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, session)
    is_owner = bid && Businesses.owner?(user, bid)

    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:current_business_id, bid)
     |> assign(:my_businesses, businesses)
     |> assign(:is_business_owner, is_owner == true)
     |> assign(:stats, Admin.dashboard_stats())
     |> assign(:gifts, Gifts.list_recent_gifts())
     |> assign(
       :gift_form,
       to_form(%{"recipient_email" => "", "duration_days" => "30", "admin_message" => ""}, as: :gift)
     )
     |> RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(user)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_gift", %{"gift" => params}, socket) do
    {:noreply, assign(socket, :gift_form, to_form(params, as: :gift))}
  end

  def handle_event("send_gift", %{"gift" => params}, socket) do
    admin = socket.assigns.current_scope.user

    attrs = %{
      recipient_email: Map.get(params, "recipient_email"),
      duration_days: Map.get(params, "duration_days"),
      admin_message: Map.get(params, "admin_message")
    }

    redeem_url_fun = fn token ->
      RompCrmWeb.Endpoint.url()
      |> String.trim_trailing("/")
      |> Kernel.<>(RompCrmWeb.Endpoint.path("/gift/claim/#{token}"))
    end

    case Gifts.create_and_email(admin, attrs, redeem_url_fun) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gift sent.")
         |> assign(:stats, Admin.dashboard_stats())
         |> assign(:gifts, Gifts.list_recent_gifts())
         |> assign(
           :gift_form,
           to_form(%{"recipient_email" => "", "duration_days" => "30", "admin_message" => ""}, as: :gift)
         )}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         socket
         |> put_flash(:error, format_cs_errors(cs))
         |> assign(:gift_form, to_form(cs, as: :gift))}

      {:error, :invalid_recipient} ->
        {:noreply, put_flash(socket, :error, "Enter a valid recipient email.")}

      {:error, :invalid_duration} ->
        {:noreply, put_flash(socket, :error, "Choose a duration between 1 and 3650 days.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not send the gift email. Try again.")}
    end
  end

  defp format_cs_errors(cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def handle_info({:sms_assistant_intro, :updated, user}, socket) do
    {:noreply, RompCrmWeb.UserAuth.apply_sms_assistant_intro_assigns(socket, user)}
  end
end
