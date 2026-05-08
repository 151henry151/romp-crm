defmodule RompCrmWeb.SubscribeController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts.{Scope, User}
  alias RompCrm.Billing
  alias RompCrm.Repo

  @doc """
  Browser return after PayPal approves subscription approval.
  """
  def paypal_return(conn, params) do
    subscription_id = Billing.paypal_return_subscription_id(params)

    conn = clear_paywall_session(conn)

    if subscription_id == "" do
      conn
      |> put_flash(:error, "Missing subscription reference from PayPal. Try subscribing again.")
      |> redirect(to: ~p"/users/register")
    else
      handle_activation(conn, subscription_id)
    end
  end

  defp handle_activation(conn, subscription_id) do
    case Billing.activate_from_paypal_subscription_id(subscription_id) do
      {:ok, _user} ->
        conn
        |> put_flash(
          :info,
          subscription_confirmed_flash(Billing.paypal_trial_days())
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, :unknown_subscription} ->
        conn
        |> put_flash(
          :error,
          "We could not match that payment to your sign-up yet. Wait a minute and try signing in — or subscribe again."
        )
        |> redirect(to: ~p"/users/register")

      {:error, {:not_active, _status}} ->
        conn
        |> put_flash(
          :error,
          "PayPal has not activated the subscription yet. Try again in a moment."
        )
        |> redirect(to: ~p"/users/register")

      {:error, {:paypal_subscription_fetch, _}} ->
        conn
        |> put_flash(
          :error,
          "Could not verify your subscription with PayPal yet. Wait a minute and try signing in — confirmation may still be processing."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not confirm your subscription. Try again or contact support.")
        |> redirect(to: ~p"/users/register")
    end
  end

  @doc """
  Browser return when the buyer cancels on PayPal.
  """
  def paypal_cancel(conn, _params) do
    conn = clear_paywall_session(conn)

    conn
    |> put_flash(:info, "Checkout was cancelled. You can choose a plan and try again when ready.")
    |> redirect(to: ~p"/subscribe")
  end

  @doc """
  Explains next steps and supports resuming checkout if the session still holds a pending user id.

  If the viewer is logged in, has a stored PayPal subscription id, and the DB still shows a
  non-active paywall state, attempts one activation sync against PayPal and redirects to **`/`**
  when PayPal reports an active subscription (fixes users stuck after checkout when the browser
  return path or webhook did not update the row yet).
  """
  def show(conn, _params) do
    case sync_subscription_with_paypal_if_needed(conn) do
      {:redirect, conn} ->
        conn

      {:show, conn} ->
        render(conn, :show,
          paywall: Billing.paywall_enabled?(),
          pending_user: pending_paywall_user(conn),
          paypal_trial_days: Billing.paypal_trial_days()
        )
    end
  end

  defp sync_subscription_with_paypal_if_needed(conn) do
    user = scope_logged_in_user(conn)

    if Billing.paywall_enabled?() && user && is_binary(user.paypal_subscription_id) &&
         not Billing.subscription_active?(user) do
      case Billing.activate_from_paypal_subscription_id(user.paypal_subscription_id) do
        {:ok, _} ->
          {:redirect,
           conn
           |> put_flash(:info, "Your subscription is active — welcome to Romp CRM.")
           |> redirect(to: ~p"/")}

        {:error, _} ->
          {:show, conn}
      end
    else
      {:show, conn}
    end
  end

  defp scope_logged_in_user(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: %User{} = user} -> user
      _ -> nil
    end
  end

  defp subscription_confirmed_flash(0),
    do: "Subscription confirmed — check email for your sign-in link to access Romp CRM."

  defp subscription_confirmed_flash(days),
    do:
      "Subscription confirmed — your #{days}-day trial has started (no subscription charge until the trial ends). Check email for your sign-in link to access Romp CRM."

  @doc """
  Re-starts hosted PayPal checkout for the pending user referenced by the encrypted session cookie.
  """
  def resume(conn, %{"plan" => plan} = _) do
    user = pending_paywall_user(conn)

    cond do
      not Billing.paywall_enabled?() ->
        conn
        |> put_flash(:info, "Subscription checkout is optional on this server.")
        |> redirect(to: ~p"/users/log-in")

      user == nil ->
        conn
        |> put_flash(:error, "Session expired — register again or sign in if you already paid.")
        |> redirect(to: ~p"/users/register")

      not Billing.valid_plan?(plan) or not Billing.plan_configured?(plan) ->
        conn
        |> put_flash(:error, "Choose a valid plan.")
        |> redirect(to: ~p"/subscribe")

      true ->
        case Billing.start_paypal_checkout(
               user,
               plan,
               paypal_return_fun(conn),
               paypal_cancel_fun(conn)
             ) do
          {:ok, %{approve_url: approve}} ->
            conn
            |> redirect(external: approve)

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not reach PayPal. Try again shortly.")
            |> redirect(to: ~p"/subscribe")
        end
    end
  end

  def resume(conn, _) do
    conn
    |> put_flash(:error, "Pick monthly or yearly billing.")
    |> redirect(to: ~p"/subscribe")
  end

  defp paypal_return_fun(conn),
    do: fn -> url(conn, ~p"/subscribe/paypal/return") end

  defp paypal_cancel_fun(conn),
    do: fn -> url(conn, ~p"/subscribe/paypal/cancel") end

  defp pending_paywall_user(conn) do
    case get_session(conn, :pending_paywall_user_id) do
      id when is_integer(id) ->
        Repo.get(User, id)

      _ ->
        nil
    end
  end

  defp clear_paywall_session(conn) do
    conn
    |> configure_session(drop: [:pending_paywall_user_id, :pending_paywall_plan])
  end
end
