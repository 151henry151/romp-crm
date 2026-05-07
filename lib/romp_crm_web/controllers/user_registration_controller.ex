defmodule RompCrmWeb.UserRegistrationController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrm.Accounts.User
  alias RompCrmWeb.UserAuth

  plug :auth_pages_no_store when action in [:new]

  defp auth_pages_no_store(conn, _opts), do: UserAuth.put_auth_pages_no_store(conn)

  def new(conn, params) do
    initial_email =
      params
      |> Map.get("email", "")
      |> to_string()
      |> String.trim()

    changeset = Accounts.change_user_email(%User{email: initial_email})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        conn
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
