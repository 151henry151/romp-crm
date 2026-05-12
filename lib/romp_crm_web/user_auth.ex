defmodule RompCrmWeb.UserAuth do
  use RompCrmWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias RompCrm.Accounts
  alias RompCrm.Accounts.Scope
  alias RompCrm.Accounts.User
  alias RompCrm.Billing
  alias RompCrm.Businesses

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_romp_crm_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn =
      conn
      |> create_or_extend_session(user, params)

    conn
    |> redirect(to: user_return_to || signed_in_path_for_user(user))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      RompCrmWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        nil
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    put_session(conn, :user_token, token)
  end

  @doc """
  Plug for routes that require sudo mode.
  """
  def require_sudo_mode(conn, _opts) do
    if Accounts.sudo_mode?(conn.assigns.current_scope.user, -10) do
      conn
    else
      conn
      |> put_flash(:error, "You must re-authenticate to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Plug for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    user = scope_user(conn.assigns[:current_scope])

    if user do
      conn
      |> redirect(to: signed_in_path_for_user(user))
      |> halt()
    else
      conn
    end
  end

  defp scope_user(%Scope{user: %User{} = user}), do: user
  defp scope_user(_), do: nil

  defp signed_in_path_for_user(%User{} = user) do
    cond do
      not Billing.paywall_enabled?() ->
        ~p"/"

      Billing.subscription_active?(user) ->
        ~p"/"

      true ->
        ~p"/subscribe"
    end
  end

  @doc """
  LiveView on_mount hook — halts and redirects if not logged in.
  """
  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  # Runs after `:require_authenticated`; blocks unpaid users when the subscription paywall is enabled.
  def on_mount(:require_active_subscription, _params, _session, socket) do
    user = socket.assigns.current_scope.user

    cond do
      not Billing.paywall_enabled?() ->
        {:cont, socket}

      Billing.subscription_active?(user) ->
        {:cont, socket}

      true ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           "An active subscription is required to access Romp CRM on this server."
         )
         |> Phoenix.LiveView.redirect(to: ~p"/subscribe")}
    end
  end

  # Requires `:require_authenticated` to run first. Assigns `current_business_id` and `my_businesses`.
  @doc false
  def on_mount(:ensure_business_scope, _params, session, socket) do
    user = socket.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)

    cond do
      businesses == [] ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:info, "Create or join a business to see jobs.")
         |> Phoenix.LiveView.redirect(to: ~p"/businesses")}

      true ->
        bid = Businesses.resolve_active_business_id(user, businesses, session)

        {:cont,
         socket
         |> Phoenix.Component.assign(:current_business_id, bid)
         |> Phoenix.Component.assign(:my_businesses, businesses)}
    end
  end

  @doc """
  Requires **`Businesses.owner?/2`** for **`current_business_id`**.

  Run after **`:ensure_business_scope`**.
  """
  def on_mount(:require_business_owner, _params, _session, socket) do
    user = socket.assigns.current_scope.user
    bid = socket.assigns.current_business_id

    if Businesses.owner?(user, bid) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Only a business owner can manage employees.")
       |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      case session["user_token"] &&
             Accounts.get_user_by_session_token(session["user_token"]) do
        {user, _} -> Scope.for_user(user)
        _ -> Scope.for_user(nil)
      end
    end)
  end

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> maybe_put_auth_required_flash()
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp maybe_put_auth_required_flash(%{path_info: []} = conn), do: conn

  defp maybe_put_auth_required_flash(conn) do
    put_flash(conn, :error, "You must log in to access this page.")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc """
  Plug for authenticated routes when `SUBSCRIPTION_PAYWALL_ENABLED` is true — requires `subscription_status` active.

  Before redirecting to **`/subscribe`**, if the user row still shows non-active but has a stored
  **`paypal_subscription_id`**, calls PayPal once to sync activation (covers checkout completed while
  the browser return path or webhook had not updated SQLite yet).
  """
  def require_active_subscription_user(conn, _opts) do
    cond do
      not Billing.paywall_enabled?() ->
        conn

      Billing.subscription_active?(conn.assigns.current_scope.user) ->
        conn

      true ->
        conn =
          case conn.assigns.current_scope.user do
            %User{paypal_subscription_id: sub_id} = u
            when is_binary(sub_id) and sub_id != "" ->
              if Billing.subscription_active?(u) do
                conn
              else
                case Billing.activate_from_paypal_subscription_id(sub_id) do
                  {:ok, refreshed} ->
                    assign(conn, :current_scope, Scope.for_user(refreshed))

                  {:error, _} ->
                    conn
                end
              end

            _ ->
              conn
          end

        if Billing.subscription_active?(conn.assigns.current_scope.user) do
          conn
        else
          conn
          |> put_flash(:error, "An active subscription is required to continue.")
          |> redirect(to: ~p"/subscribe")
          |> halt()
        end
    end
  end

  @doc false
  def put_auth_pages_no_store(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store, must-revalidate")
    |> put_resp_header("pragma", "no-cache")
  end
end
