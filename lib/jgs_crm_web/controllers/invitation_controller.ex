defmodule JgsCrmWeb.InvitationController do
  use JgsCrmWeb, :controller

  alias JgsCrm.Businesses

  def show(conn, %{"token" => token}) do
    token = URI.decode(token)

    case Businesses.get_invitation_by_raw_token(token) do
      nil ->
        conn
        |> put_flash(:error, "That invitation is invalid or has expired.")
        |> redirect(to: ~p"/users/log-in")

      invitation ->
        scope = conn.assigns[:current_scope]

        cond do
          scope && scope.user &&
              String.downcase(String.trim(scope.user.email)) ==
                String.downcase(String.trim(invitation.email)) ->
            case Businesses.accept_invitation_raw(token, scope.user) do
              {:ok, business} ->
                conn
                |> put_flash(:info, "You joined #{business.name}.")
                |> redirect(to: ~p"/")

              {:error, :email_mismatch} ->
                conn
                |> put_flash(:error, "You must be logged in as #{invitation.email} to accept.")
                |> redirect(to: ~p"/")

              {:error, _} ->
                conn
                |> put_flash(:error, "Could not accept the invitation.")
                |> redirect(to: ~p"/")
            end

          scope && scope.user ->
            conn
            |> put_flash(
              :error,
              "This invitation is for #{invitation.email}. Log in with that address or ask for a new invite."
            )
            |> redirect(to: ~p"/users/settings")

          true ->
            conn
            |> put_session("pending_invitation_token", token)
            |> put_flash(:info, "Sign in or register as #{invitation.email} to join.")
            |> redirect(to: ~p"/users/log-in")
        end
    end
  end
end
