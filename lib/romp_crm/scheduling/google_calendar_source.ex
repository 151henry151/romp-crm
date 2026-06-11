defmodule RompCrm.Scheduling.GoogleCalendarSource do
  @moduledoc """
  Read-only Google Calendar `CalendarSource`: queries the freeBusy endpoint for
  the user's primary calendar. Only busy intervals are read — never event
  titles, attendees, or descriptions.

  Credential map (encrypted at rest): `access_token`, `refresh_token`,
  `expires_at` (unix seconds). Tokens are refreshed transparently and persisted.

  OAuth client config: `config :romp_crm, :google_calendar_oauth, client_id: ..., client_secret: ...`
  """

  @behaviour RompCrm.Scheduling.CalendarSource

  require Logger

  alias RompCrm.Scheduling.CalendarCredential
  alias RompCrm.Scheduling.CalendarCredentials

  @token_url "https://oauth2.googleapis.com/token"
  @freebusy_url "https://www.googleapis.com/calendar/v3/freeBusy"
  @auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @scope "https://www.googleapis.com/auth/calendar.freebusy"
  @refresh_margin_seconds 60

  ## OAuth helpers (used by the settings controller)

  def oauth_configured? do
    oauth = Application.get_env(:romp_crm, :google_calendar_oauth) || []
    is_binary(Keyword.get(oauth, :client_id)) and is_binary(Keyword.get(oauth, :client_secret))
  end

  @doc "Consent URL requesting offline, read-only freebusy access."
  def authorize_url(redirect_uri, state) do
    oauth = Application.get_env(:romp_crm, :google_calendar_oauth) || []

    query =
      URI.encode_query(%{
        "client_id" => Keyword.get(oauth, :client_id),
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => @scope,
        "access_type" => "offline",
        "prompt" => "consent",
        "state" => state
      })

    @auth_url <> "?" <> query
  end

  @doc "Exchanges an authorization code for a credential map ready to store."
  def exchange_code(code, redirect_uri) do
    oauth = Application.get_env(:romp_crm, :google_calendar_oauth) || []

    form = [
      client_id: Keyword.get(oauth, :client_id),
      client_secret: Keyword.get(oauth, :client_secret),
      code: code,
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    ]

    case Req.post(@token_url, [form: form] ++ http_options()) do
      {:ok, %{status: 200, body: %{"access_token" => access} = body}} ->
        {:ok,
         %{
           "access_token" => access,
           "refresh_token" => body["refresh_token"],
           "expires_at" => System.os_time(:second) + parse_int(body["expires_in"], 3600)
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:google_code_exchange, status, body}}

      {:error, reason} ->
        {:error, {:request, reason}}
    end
  end

  @impl true
  def fetch_busy_blocks(%CalendarCredential{} = cred, {from_date, to_date}, timezone) do
    with {:ok, creds} <- CalendarCredentials.decrypt_credentials(cred),
         {:ok, creds, cred} <- ensure_fresh_token(creds, cred),
         {:ok, blocks} <- query_freebusy(creds, from_date, to_date, timezone) do
      _ = CalendarCredentials.mark_synced(cred)
      {:ok, blocks}
    else
      {:error, reason} ->
        _ = CalendarCredentials.mark_error(cred, inspect(reason))
        {:error, reason}

      :error ->
        _ = CalendarCredentials.mark_error(cred, "credential decrypt failed")
        {:error, :decrypt_failed}
    end
  end

  defp ensure_fresh_token(creds, cred) do
    expires_at = parse_int(creds["expires_at"])
    now = System.os_time(:second)

    if is_integer(expires_at) and expires_at > now + @refresh_margin_seconds do
      {:ok, creds, cred}
    else
      refresh_token(creds, cred)
    end
  end

  defp refresh_token(%{"refresh_token" => refresh} = creds, cred)
       when is_binary(refresh) and refresh != "" do
    oauth = Application.get_env(:romp_crm, :google_calendar_oauth) || []

    form = [
      client_id: Keyword.get(oauth, :client_id),
      client_secret: Keyword.get(oauth, :client_secret),
      refresh_token: refresh,
      grant_type: "refresh_token"
    ]

    case Req.post(@token_url, [form: form] ++ http_options()) do
      {:ok, %{status: 200, body: %{"access_token" => access} = body}} ->
        new_creds =
          creds
          |> Map.put("access_token", access)
          |> Map.put("expires_at", System.os_time(:second) + parse_int(body["expires_in"], 3600))

        case CalendarCredentials.update_credentials(cred, new_creds) do
          {:ok, cred} -> {:ok, new_creds, cred}
          {:error, _} = err -> err
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:google_token_refresh, status, body}}

      {:error, reason} ->
        {:error, {:request, reason}}
    end
  end

  defp refresh_token(_creds, _cred), do: {:error, :missing_refresh_token}

  defp query_freebusy(creds, from_date, to_date, timezone) do
    time_min = day_start_utc(from_date, timezone)
    time_max = day_start_utc(Date.add(to_date, 1), timezone)

    body = %{
      timeMin: DateTime.to_iso8601(time_min),
      timeMax: DateTime.to_iso8601(time_max),
      items: [%{id: "primary"}]
    }

    opts =
      [
        json: body,
        headers: [{"authorization", "Bearer #{creds["access_token"]}"}]
      ] ++ http_options()

    case Req.post(@freebusy_url, opts) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, parse_busy(resp)}

      {:ok, %{status: status, body: resp}} ->
        {:error, {:google_freebusy, status, summarize_error(resp)}}

      {:error, reason} ->
        {:error, {:request, reason}}
    end
  end

  defp parse_busy(%{"calendars" => calendars}) when is_map(calendars) do
    calendars
    |> Map.values()
    |> Enum.flat_map(fn cal -> List.wrap(cal["busy"]) end)
    |> Enum.flat_map(fn
      %{"start" => s, "end" => e} ->
        with {:ok, start_dt, _} <- DateTime.from_iso8601(to_string(s)),
             {:ok, end_dt, _} <- DateTime.from_iso8601(to_string(e)) do
          [%{start: DateTime.truncate(start_dt, :second), end: DateTime.truncate(end_dt, :second)}]
        else
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.sort_by(& &1.start, DateTime)
  end

  defp parse_busy(_), do: []

  defp day_start_utc(date, timezone) do
    case DateTime.new(date, ~T[00:00:00], timezone) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:gap, _b, a} -> DateTime.shift_zone!(a, "Etc/UTC")
      {:ambiguous, f, _s} -> DateTime.shift_zone!(f, "Etc/UTC")
    end
  end

  defp summarize_error(resp) when is_map(resp), do: resp |> Map.take(["error"]) |> inspect()
  defp summarize_error(resp), do: resp |> to_string() |> String.slice(0, 200)

  defp parse_int(v, fallback \\ nil)
  defp parse_int(v, _fallback) when is_integer(v), do: v

  defp parse_int(v, fallback) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> fallback
    end
  end

  defp parse_int(_, fallback), do: fallback

  defp http_options do
    (Application.get_env(:romp_crm, :calendar_http_options) || []) ++
      [finch: RompCrm.Finch, receive_timeout: 30_000]
  end
end
