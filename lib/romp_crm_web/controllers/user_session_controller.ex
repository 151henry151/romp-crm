defmodule RompCrmWeb.UserSessionController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrmWeb.UserAuth

  plug :auth_pages_no_store when action in [:new, :confirm]

  defp auth_pages_no_store(conn, _opts), do: UserAuth.put_auth_pages_no_store(conn)

  def new(conn, params) do
    conn = maybe_put_gift_return_to(conn, params["gift"])

    email_from_query = login_prefill_email(params["email"])
    email_from_scope = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    email =
      if email_from_query != "" do
        email_from_query
      else
        email_from_scope || ""
      end

    after_gift? = params["after_gift"] == "1"
    form = Phoenix.Component.to_form(%{"email" => email}, as: "user")

    render(conn, :new, form: form, after_gift: after_gift?)
  end

  defp login_prefill_email(email) when is_binary(email),
    do: email |> String.trim() |> String.slice(0, 200)

  defp login_prefill_email(_), do: ""

  defp maybe_put_gift_return_to(conn, gift_raw) do
    token = gift_raw |> to_string() |> String.trim()

    if token != "" and RompCrm.Gifts.claimable_gift_token?(token) do
      put_session(conn, :user_return_to, ~p"/gift/claim/#{token}")
    else
      conn
    end
  end

  # magic link login
  def create(conn, %{"user" => %{"token" => token} = user_params} = params) do
    info =
      case params do
        %{"_action" => "confirmed"} -> "User confirmed successfully."
        _ -> "Welcome back!"
      end

    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> render(:new, form: Phoenix.Component.to_form(%{}, as: "user"), after_gift: false)
    end
  end

  # email + password login
  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      form = Phoenix.Component.to_form(user_params, as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> render(:new, form: form, after_gift: false)
    end
  end

  # magic link request
  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/users/log-in")
  end

  def confirm(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

      conn
      |> assign(:user, user)
      |> assign(:form, form)
      |> render(:confirm)
    else
      conn
      |> put_flash(:error, "Magic link is invalid or it has expired.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
