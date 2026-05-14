defmodule RompCrmWeb.GiftRedeemController do
  use RompCrmWeb, :controller

  alias RompCrm.Gifts
  alias RompCrmWeb.UserAuth

  plug :auth_pages_no_store when action in [:show]

  defp auth_pages_no_store(conn, _opts), do: UserAuth.put_auth_pages_no_store(conn)

  def show(conn, %{"token" => token}) do
    conn =
      if conn.assigns.current_scope && conn.assigns.current_scope.user do
        conn
      else
        put_session(conn, :user_return_to, ~p"/gift/redeem/#{token}")
      end

    case Gifts.get_gift_by_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(:invalid)

      %_{redeemed_at: %DateTime{}} ->
        conn
        |> put_status(:gone)
        |> render(:already_redeemed)

      gift ->
        render(conn, :show, gift: gift, token: token)
    end
  end

  def create(conn, %{"token" => token}) do
    user = conn.assigns.current_scope.user

    case Gifts.redeem_for_logged_in_user(user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Gift applied. Welcome back to Romp CRM.")
        |> redirect(to: ~p"/")

      {:error, :invalid_gift} ->
        conn
        |> put_flash(:error, "That gift link is not valid.")
        |> redirect(to: ~p"/users/log-in")

      {:error, :already_redeemed} ->
        conn
        |> put_flash(:error, "This gift was already redeemed.")
        |> redirect(to: ~p"/")

      {:error, :email_mismatch} ->
        expected =
          case Gifts.get_gift_by_token(token) do
            %{recipient_email: e} -> e
            _ -> "the gifted email address"
          end

        conn
        |> put_flash(
          :error,
          "This gift is for #{expected}. Log in with that email to redeem."
        )
        |> redirect(to: ~p"/gift/redeem/#{token}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not apply the gift. Try again.")
        |> redirect(to: ~p"/gift/redeem/#{token}")
    end
  end
end
