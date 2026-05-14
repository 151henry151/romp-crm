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

  def update(conn, %{"action" => "export_email_now"} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, kinds} <- DataExport.normalize_export_kinds(params),
         {:ok, business_ids} <- DataExport.normalize_export_business_ids(user, params) do
      case DataExport.deliver_email_export(user, kinds, business_ids) do
        {:ok, :sent} ->
          conn
          |> put_flash(:info, export_email_sent_flash(kinds, length(business_ids)))
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
    else
      {:error, :none_selected} ->
        conn
        |> put_flash(
          :error,
          "Choose at least one export: Jobs, Employees, Time log, or Audit log."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, :no_business_selected} ->
        conn
        |> put_flash(
          :error,
          "Choose at least one workspace to export (only businesses you create as owner are listed)."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, :no_owned_businesses} ->
        conn
        |> put_flash(
          :error,
          "You do not own any businesses yet, so there is nothing to export. Create a business first."
        )
        |> redirect(to: ~p"/users/settings")
    end
  end

  def update(conn, %{"action" => "export_download"} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, kinds} <- DataExport.normalize_export_kinds(params),
         {:ok, business_ids} <- DataExport.normalize_export_business_ids(user, params) do
      files = DataExport.build_export_files(business_ids, kinds)

      case DataExport.build_download_payload(files) do
        {:ok, {:one, name, body}} ->
          conn
          |> put_resp_content_type("text/csv; charset=utf-8")
          |> put_resp_header("content-disposition", ~s(attachment; filename="#{name}"))
          |> send_resp(200, body)

        {:ok, {:zip, body}} ->
          zip_name = "romp-crm-export-#{Date.utc_today()}.zip"

          conn
          |> put_resp_content_type("application/zip")
          |> put_resp_header("content-disposition", ~s(attachment; filename="#{zip_name}"))
          |> send_resp(200, body)

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not build the download. (#{inspect(reason)})")
          |> redirect(to: ~p"/users/settings")
      end
    else
      {:error, :none_selected} ->
        conn
        |> put_flash(
          :error,
          "Choose at least one export: Jobs, Employees, Time log, or Audit log."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, :no_business_selected} ->
        conn
        |> put_flash(
          :error,
          "Choose at least one workspace to export (only businesses you create as owner are listed)."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, :no_owned_businesses} ->
        conn
        |> put_flash(
          :error,
          "You do not own any businesses yet, so there is nothing to download. Create a business first."
        )
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
    %{"user" => user_params} = merge_sms_reminder_prefs_from_form(params)
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

  defp export_email_sent_flash(kinds, workspace_count) do
    names =
      kinds
      |> Enum.map(&export_csv_filename/1)
      |> Enum.join(", ")

    ws =
      if workspace_count == 1 do
        "1 workspace"
      else
        "#{workspace_count} workspaces"
      end

    "Check your email for CSV attachments: #{names}. (#{ws}.)"
  end

  defp export_csv_filename(:jobs), do: "jobs.csv"
  defp export_csv_filename(:employees), do: "employees.csv"
  defp export_csv_filename(:time_log), do: "time_log.csv"
  defp export_csv_filename(:audit_log), do: "audit_log.csv"

  defp merge_sms_reminder_prefs_from_form(%{"user" => inner} = params) when is_map(inner) do
    inner =
      if Map.has_key?(inner, "sms_reminder_send_hour_utc") do
        offsets = normalize_reminder_offsets_param(Map.get(inner, "sms_reminder_offsets"))
        hour = normalize_reminder_hour_param(Map.get(inner, "sms_reminder_send_hour_utc"))
        json = Jason.encode!(%{"job_offsets" => offsets, "send_hour_utc" => hour})

        inner
        |> Map.put("sms_reminder_prefs_json", json)
        |> Map.drop(["sms_reminder_offsets", "sms_reminder_send_hour_utc"])
      else
        inner
      end

    %{params | "user" => inner}
  end

  defp merge_sms_reminder_prefs_from_form(params), do: params

  defp normalize_reminder_offsets_param(raw) do
    raw
    |> List.wrap()
    |> Enum.map(&parse_reminder_offset/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort(:desc)
    |> case do
      [] -> [1, 0]
      list -> list
    end
  end

  defp parse_reminder_offset(v) when v in [0, 1, 2, 3, 7], do: v

  defp parse_reminder_offset(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} when n in [0, 1, 2, 3, 7] -> n
      _ -> nil
    end
  end

  defp parse_reminder_offset(_), do: nil

  defp normalize_reminder_hour_param(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {h, _} when h >= 0 and h <= 23 -> h
      _ -> 13
    end
  end

  defp normalize_reminder_hour_param(h) when is_integer(h) and h >= 0 and h <= 23, do: h
  defp normalize_reminder_hour_param(_), do: 13

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
