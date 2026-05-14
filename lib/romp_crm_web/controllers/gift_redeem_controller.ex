defmodule RompCrmWeb.GiftRedeemController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrm.Gifts
  alias RompCrmWeb.UserAuth

  plug :auth_pages_no_store when action in [:redirect_claim, :claim]

  defp auth_pages_no_store(conn, _opts), do: UserAuth.put_auth_pages_no_store(conn)

  def redirect_claim(conn, %{"token" => token}) do
    redirect(conn, to: ~p"/gift/claim/#{token}")
  end

  def claim(conn, %{"token" => token}) do
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
        claim_valid_gift(conn, gift, token)
    end
  end

  defp claim_valid_gift(conn, gift, token) do
    current = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    cond do
      current && email_matches_gift?(current.email, gift.recipient_email) ->
        finish_logged_in_redeem(conn, current, token)

      current ->
        conn
        |> put_flash(
          :error,
          "This gift is for #{gift.recipient_email}. You are signed in as #{current.email}. Log out and sign in with the gifted email, or use a private window."
        )
        |> render(:show, gift: gift, token: token)

      true ->
        claim_anonymous(conn, gift, token)
    end
  end

  defp claim_anonymous(conn, gift, token) do
    cond do
      Accounts.get_user_by_email(gift.recipient_email) ->
        conn
        |> put_session(:user_return_to, ~p"/gift/claim/#{token}")
        |> redirect(
          to: ~p"/users/log-in?#{[email: gift.recipient_email, after_gift: "1"]}"
        )

      true ->
        case Gifts.claim_creates_user(gift) do
          {:ok, user} ->
            conn
            |> put_flash(:info, "Welcome! Your gifted subscription is active.")
            |> UserAuth.log_in_user(user, %{})

          {:error, :user_exists} ->
            conn
            |> put_session(:user_return_to, ~p"/gift/claim/#{token}")
            |> redirect(
              to: ~p"/users/log-in?#{[email: gift.recipient_email, after_gift: "1"]}"
            )

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not activate your gift from this link. Try again or contact support.")
            |> redirect(to: ~p"/users/log-in?#{[email: gift.recipient_email]}")
        end
    end
  end

  defp finish_logged_in_redeem(conn, user, token) do
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
        conn
        |> put_flash(:error, "This gift is for a different email address.")
        |> redirect(to: ~p"/gift/claim/#{token}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not apply the gift. Try again.")
        |> redirect(to: ~p"/gift/claim/#{token}")
    end
  end

  defp email_matches_gift?(user_email, gift_recipient_email) do
    String.downcase(String.trim(user_email)) == gift_recipient_email
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
        |> redirect(to: ~p"/gift/claim/#{token}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not apply the gift. Try again.")
        |> redirect(to: ~p"/gift/claim/#{token}")
    end
  end
end
