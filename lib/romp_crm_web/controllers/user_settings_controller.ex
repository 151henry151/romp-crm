defmodule RompCrmWeb.UserSettingsController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrm.Billing
  alias RompCrm.Businesses
  alias RompCrm.DataExport
  alias RompCrmWeb.UserAuth

  import RompCrmWeb.UserAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_mode
  plug :assign_email_and_password_changesets
  plug :assign_workspace_nav_for_layout

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "export_data_now"} = _params) do
    user = conn.assigns.current_scope.user

    case DataExport.deliver_email_export(user) do
      {:ok, :sent} ->
        conn
        |> put_flash(
          :info,
          "Check your email for CSV attachments: jobs, employees, time log, and SMS interaction log."
        )
        |> redirect(to: ~p"/users/settings")

      {:ok, :skipped_no_owned_businesses} ->
        conn
        |> put_flash(
          :info,
          "We sent a short email: this account does not own any businesses yet, so there were no CSV rows to attach."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not send export right now. (#{inspect(reason)})")
        |> redirect(to: ~p"/users/settings")
    end
  end

  def update(conn, %{"action" => "update_data_export_schedule"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_export_settings(user, user_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Scheduled data export settings saved.")
        |> redirect(to: ~p"/users/settings")

      {:error, %Ecto.Changeset{} = cs} ->
        render(conn, :edit, export_changeset: cs)
    end
  end

  def update(conn, %{"action" => "cancel_subscription"} = _) do
    user = conn.assigns.current_scope.user

    case Billing.cancel_subscription_for_user(user) do
      {:ok, _} ->
        conn
        |> put_flash(
          :info,
          "Your PayPal subscription has been cancelled. You can resubscribe anytime from the subscription page."
        )
        |> redirect(to: ~p"/subscribe")

      {:error, :not_cancellable} ->
        conn
        |> put_flash(:error, "There is no active hosted subscription to cancel on this account.")
        |> redirect(to: ~p"/users/settings")

      {:error, {:paypal_cancel_failed, _reason}} ->
        conn
        |> put_flash(
          :error,
          "PayPal could not cancel the subscription right now. Try again in a few minutes, or cancel automatic payments in your PayPal account."
        )
        |> redirect(to: ~p"/users/settings")
    end
  end

  def update(conn, %{"action" => "update_profile"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Profile updated.")
        |> redirect(to: ~p"/users/settings")

      {:error, %Ecto.Changeset{} = cs} ->
        render(conn, :edit, profile_changeset: cs)
    end
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/users/settings")

      changeset ->
        render(conn, :edit, email_changeset: %{changeset | action: :insert})
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit, password_changeset: changeset)
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_scope.user

    paypal_sub_id = user.paypal_subscription_id

    show_subscription_help =
      RompCrm.ApplicationConfig.subscription_paywall_enabled?() and is_binary(paypal_sub_id) and
        String.trim(paypal_sub_id) != ""

    show_cancel_subscription =
      RompCrm.ApplicationConfig.subscription_paywall_enabled?() and
        user.subscription_status == "active" and
        is_binary(paypal_sub_id) and String.trim(paypal_sub_id) != ""

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
    |> assign(:profile_changeset, Accounts.change_user_profile(user))
    |> assign(:export_changeset, Accounts.change_user_export_settings(user))
    |> assign(:profile_businesses, Businesses.list_businesses_for_user(user))
    |> assign(:owned_businesses_for_export, Businesses.list_owned_businesses_for_user(user))
    |> assign(:show_paypal_subscription_help, show_subscription_help)
    |> assign(:show_cancel_subscription, show_cancel_subscription)
    |> assign(:paypal_trial_days, Billing.paypal_trial_days())
  end

  defp assign_workspace_nav_for_layout(conn, _opts) do
    user = conn.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    session = conn.private[:plug_session] || %{}
    bid = Businesses.resolve_active_business_id(user, businesses, session)
    is_owner = bid != nil && Businesses.owner?(user, bid)

    conn
    |> assign(:show_workspace_nav, businesses != [])
    |> assign(:current_business_id, bid)
    |> assign(:my_businesses, businesses)
    |> assign(:is_business_owner, is_owner)
  end
end
