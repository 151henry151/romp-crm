defmodule RompCrmWeb.CalendarSettingsController do
  @moduledoc """
  Scheduling preferences and external calendar connections (Google OAuth,
  Apple iCloud app-specific password) from the account settings page.
  """

  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrm.Scheduling.CalendarCredentials
  alias RompCrm.Scheduling.GoogleCalendarSource
  alias RompCrm.Scheduling.{Playbook, Prefs, TimezoneInference}

  @settings_path "/users/settings"

  ## Scheduling preferences

  def update_scheduling(conn, params) do
    user = conn.assigns.current_scope.user
    raw = Map.get(params, "prefs") || %{}

    tz =
      case Map.get(raw, "timezone") |> to_string() |> String.trim() do
        "" ->
          user.phone_normalized
          |> Kernel.||(user.phone)
          |> TimezoneInference.from_phone()
          |> then(fn inferred ->
            case TimezoneInference.from_conn(conn) do
              ^inferred -> inferred
              conn_tz when inferred == "America/New_York" -> conn_tz
              _ -> inferred
            end
          end)

        explicit ->
          explicit
      end

    prefs =
      Prefs.decode(
        Jason.encode!(%{
          "timezone" => tz,
          "workday_start" => Map.get(raw, "workday_start"),
          "workday_end" => Map.get(raw, "workday_end"),
          "work_days" => parse_work_days(Map.get(raw, "work_days")),
          "buffer_minutes" => parse_int(Map.get(raw, "buffer_minutes")),
          "customer_outreach_style" => Map.get(raw, "customer_outreach_style"),
          "min_lead_days" => parse_int(Map.get(raw, "min_lead_days")),
          "scheduling_bias" => nilify_blank(Map.get(raw, "scheduling_bias"))
        })
      )

    case Accounts.update_user_scheduling_prefs(user, Prefs.encode(prefs)) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Scheduling preferences saved.")
        |> redirect(to: @settings_path)

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not save scheduling preferences.")
        |> redirect(to: @settings_path)
    end
  end

  ## Apple iCloud (CalDAV, app-specific password)

  def connect_apple(conn, params) do
    user = conn.assigns.current_scope.user
    raw = Map.get(params, "apple") || %{}
    apple_id = raw |> Map.get("apple_id", "") |> String.trim()
    app_password = raw |> Map.get("app_password", "") |> String.trim()

    if apple_id == "" or app_password == "" do
      conn
      |> put_flash(:error, "Apple ID and app-specific password are both required.")
      |> redirect(to: @settings_path)
    else
      case CalendarCredentials.connect(user.id, "apple", %{
             "apple_id" => apple_id,
             "app_password" => app_password
           }) do
        {:ok, _} ->
          conn
          |> put_flash(
            :info,
            "Apple Calendar connected. Free/busy times will be checked on the next availability lookup."
          )
          |> redirect(to: @settings_path)

        {:error, _} ->
          conn
          |> put_flash(:error, "Could not save the Apple Calendar connection.")
          |> redirect(to: @settings_path)
      end
    end
  end

  ## Disconnect (either source)

  def disconnect(conn, %{"source" => source}) when source in ["google", "apple"] do
    user = conn.assigns.current_scope.user
    :ok = CalendarCredentials.disconnect(user.id, source)

    conn
    |> put_flash(:info, "#{source_label(source)} disconnected.")
    |> redirect(to: @settings_path)
  end

  ## Google OAuth

  def google_connect(conn, _params) do
    if GoogleCalendarSource.oauth_configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

      conn
      |> put_session(:google_calendar_oauth_state, state)
      |> redirect(external: GoogleCalendarSource.authorize_url(google_redirect_uri(conn), state))
    else
      conn
      |> put_flash(:error, "Google Calendar is not configured on this server yet.")
      |> redirect(to: @settings_path)
    end
  end

  def google_callback(conn, %{"error" => _reason}) do
    conn
    |> delete_session(:google_calendar_oauth_state)
    |> put_flash(:info, "Google Calendar connection was cancelled.")
    |> redirect(to: @settings_path)
  end

  def google_callback(conn, %{"code" => code, "state" => state}) do
    user = conn.assigns.current_scope.user
    expected_state = get_session(conn, :google_calendar_oauth_state)
    conn = delete_session(conn, :google_calendar_oauth_state)

    with true <- is_binary(expected_state) and Plug.Crypto.secure_compare(state, expected_state),
         {:ok, creds} <- GoogleCalendarSource.exchange_code(code, google_redirect_uri(conn)),
         {:ok, _} <- CalendarCredentials.connect(user.id, "google", creds) do
      conn
      |> put_flash(:info, "Google Calendar connected. Busy times now count toward availability.")
      |> redirect(to: @settings_path)
    else
      _ ->
        conn
        |> put_flash(:error, "Google Calendar connection failed — please try again.")
        |> redirect(to: @settings_path)
    end
  end

  def google_callback(conn, _params) do
    conn
    |> put_flash(:error, "Google Calendar connection failed — please try again.")
    |> redirect(to: @settings_path)
  end

  ## Helpers

  defp google_redirect_uri(_conn) do
    base =
      Application.get_env(:romp_crm, :google_calendar_redirect_base) ||
        RompCrmWeb.Endpoint.url()

    base <> "/users/settings/calendars/google/callback"
  end

  defp source_label("google"), do: "Google Calendar"
  defp source_label("apple"), do: "Apple Calendar"

  defp parse_work_days(raw) do
    raw
    |> List.wrap()
    |> Enum.map(fn
      v when is_integer(v) -> v
      v when is_binary(v) -> case Integer.parse(v) do
          {i, _} -> i
          _ -> nil
        end
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} -> i
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp nilify_blank(v) when is_binary(v) do
    if String.trim(v) == "", do: nil, else: String.trim(v)
  end

  defp nilify_blank(v), do: v

  def deactivate_playbook_rule(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user
    business_id = user.selected_business_id || user.sms_business_id

    with bid when is_integer(bid) <- business_id,
         {rule_id, ""} <- Integer.parse(to_string(id)),
         {:ok, _} <- Playbook.deactivate_rule!(rule_id, bid, user.id) do
      conn
      |> put_flash(:info, "Scheduling rule removed.")
      |> redirect(to: @settings_path)
    else
      _ ->
        conn
        |> put_flash(:error, "Could not remove that rule.")
        |> redirect(to: @settings_path)
    end
  end
end
