defmodule RompCrmWeb.UserRegistrationController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrm.Accounts.User
  alias RompCrm.Billing
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

    render(conn, :new,
      changeset: changeset,
      subscription_paywall: Billing.paywall_enabled?()
    )
  end

  def create(conn, %{"user" => user_params}) do
    plan = user_params |> Map.get("plan", "monthly") |> to_string()
    attrs = Map.drop(user_params, ["plan"])

    cond do
      Billing.paywall_enabled?() and not Billing.valid_plan?(plan) ->
        conn
        |> put_flash(:error, "Choose monthly or annual billing.")
        |> render_register_form(attrs)

      Billing.paywall_enabled?() and not Billing.plan_configured?(plan) ->
        conn
        |> put_flash(
          :error,
          "This server is not configured for that plan yet. Try the other option or contact support."
        )
        |> render_register_form(attrs)

      true ->
        finish_create(conn, attrs, plan)
    end
  end

  defp render_register_form(conn, attrs) do
    cs = Accounts.change_user_email(%User{}, attrs)
    changeset = %{cs | action: :insert}

    render(conn, :new,
      changeset: changeset,
      subscription_paywall: Billing.paywall_enabled?()
    )
  end

  defp finish_create(conn, attrs, plan) do
    case Accounts.register_user(attrs) do
      {:ok, user} ->
        if Billing.paywall_enabled?() do
          return_url = fn -> url(conn, ~p"/subscribe/paypal/return") end
          cancel_url = fn -> url(conn, ~p"/subscribe/paypal/cancel") end

          case Billing.start_paypal_checkout(user, plan, return_url, cancel_url) do
            {:ok, %{approve_url: approve}} ->
              conn
              |> put_session(:pending_paywall_user_id, user.id)
              |> put_session(:pending_paywall_plan, plan)
              |> redirect(external: approve)

            {:error, _} ->
              conn
              |> put_flash(
                :error,
                "Could not start PayPal checkout. Try again in a minute or resume from the subscription page."
              )
              |> put_session(:pending_paywall_user_id, user.id)
              |> put_session(:pending_paywall_plan, plan)
              |> redirect(to: ~p"/subscribe")
          end
        else
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
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: %{changeset | action: :insert},
          subscription_paywall: Billing.paywall_enabled?()
        )
    end
  end
end
