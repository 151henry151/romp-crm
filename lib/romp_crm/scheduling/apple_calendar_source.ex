defmodule RompCrm.Scheduling.AppleCalendarSource do
  @moduledoc """
  Read-only Apple iCloud Calendar `CalendarSource` over CalDAV, authenticated
  with the user's Apple ID + an app-specific password.

  Flow: PROPFIND `/` for `current-user-principal` → PROPFIND the principal for
  `calendar-home-set` → CalDAV `free-busy-query` REPORT on the calendar home.
  Only the free/busy report is requested — event details never leave iCloud.

  Credential map (encrypted at rest): `apple_id`, `app_password`, and a cached
  `calendar_home` href after first discovery.
  """

  @behaviour RompCrm.Scheduling.CalendarSource

  require Logger

  alias RompCrm.Scheduling.CalendarCredential
  alias RompCrm.Scheduling.CalendarCredentials

  @caldav_base "https://caldav.icloud.com"

  @impl true
  def fetch_busy_blocks(%CalendarCredential{} = cred, {from_date, to_date}, timezone) do
    with {:ok, creds} <- decrypt(cred),
         {:ok, home, creds} <- calendar_home(creds, cred),
         {:ok, blocks} <- freebusy_report(creds, home, from_date, to_date, timezone) do
      _ = CalendarCredentials.mark_synced(cred)
      {:ok, blocks}
    else
      {:error, reason} ->
        _ = CalendarCredentials.mark_error(cred, inspect(reason))
        {:error, reason}
    end
  end

  defp decrypt(cred) do
    case CalendarCredentials.decrypt_credentials(cred) do
      {:ok, creds} -> {:ok, creds}
      :error -> {:error, :decrypt_failed}
    end
  end

  # ── Discovery ───────────────────────────────────────────────────────────────

  defp calendar_home(%{"calendar_home" => home} = creds, _cred)
       when is_binary(home) and home != "" do
    {:ok, home, creds}
  end

  defp calendar_home(creds, cred) do
    with {:ok, principal} <- discover_principal(creds),
         {:ok, home} <- discover_home(creds, principal) do
      new_creds = Map.put(creds, "calendar_home", home)
      _ = CalendarCredentials.update_credentials(cred, new_creds)
      {:ok, home, new_creds}
    end
  end

  defp discover_principal(creds) do
    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <propfind xmlns="DAV:"><prop><current-user-principal/></prop></propfind>
    """

    case dav_request(creds, "PROPFIND", "/", body, depth: "0") do
      {:ok, xml} ->
        case parse_href(xml, "current-user-principal") do
          nil -> {:error, :principal_not_found}
          href -> {:ok, href}
        end

      {:error, _} = err ->
        err
    end
  end

  defp discover_home(creds, principal) do
    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <propfind xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
      <prop><C:calendar-home-set/></prop>
    </propfind>
    """

    case dav_request(creds, "PROPFIND", principal, body, depth: "0") do
      {:ok, xml} ->
        case parse_href(xml, "calendar-home-set") do
          nil -> {:error, :calendar_home_not_found}
          href -> {:ok, href}
        end

      {:error, _} = err ->
        err
    end
  end

  # ── Free/busy report ────────────────────────────────────────────────────────

  defp freebusy_report(creds, home, from_date, to_date, timezone) do
    start_utc = day_start_utc(from_date, timezone)
    end_utc = day_start_utc(Date.add(to_date, 1), timezone)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <C:free-busy-query xmlns:C="urn:ietf:params:xml:ns:caldav">
      <C:time-range start="#{ics_instant(start_utc)}" end="#{ics_instant(end_utc)}"/>
    </C:free-busy-query>
    """

    case dav_request(creds, "REPORT", home, body, depth: "1") do
      {:ok, ics} -> {:ok, parse_freebusy_ics(ics)}
      {:error, _} = err -> err
    end
  end

  defp dav_request(creds, method, url_or_path, body, opts) do
    url =
      if String.starts_with?(url_or_path, "http") do
        url_or_path
      else
        @caldav_base <> url_or_path
      end

    req_opts =
      [
        method: method,
        url: url,
        body: body,
        auth: {:basic, "#{creds["apple_id"]}:#{creds["app_password"]}"},
        headers: [
          {"content-type", "application/xml; charset=utf-8"},
          {"depth", Keyword.get(opts, :depth, "0")}
        ],
        redirect: false
      ] ++ http_options()

    case Req.request(req_opts) do
      {:ok, %{status: status, body: resp}} when status in 200..299 or status == 207 ->
        {:ok, to_string(resp)}

      {:ok, %{status: status}} ->
        {:error, {:caldav_http, method, status}}

      {:error, reason} ->
        {:error, {:request, reason}}
    end
  end

  # ── Parsers (public for unit tests) ─────────────────────────────────────────

  @doc "Extracts the `<href>` inside the named element from a PROPFIND multistatus body."
  def parse_href(xml, element) when is_binary(xml) and is_binary(element) do
    regex = ~r/<(?:[\w-]+:)?#{Regex.escape(element)}[^>]*>.*?<(?:[\w-]+:)?href[^>]*>([^<]+)<\/(?:[\w-]+:)?href>/s

    case Regex.run(regex, xml) do
      [_, href] -> String.trim(href)
      _ -> nil
    end
  end

  @doc """
  Parses busy intervals from a VFREEBUSY icalendar body. Periods may be
  `start/end` or `start/duration`; `FBTYPE=FREE` periods are ignored.
  """
  def parse_freebusy_ics(ics) when is_binary(ics) do
    ~r/^FREEBUSY([^:]*):(.+)$/m
    |> Regex.scan(ics)
    |> Enum.reject(fn [_, params, _] -> String.contains?(String.upcase(params), "FBTYPE=FREE") end)
    |> Enum.flat_map(fn [_, _params, periods] ->
      periods
      |> String.trim()
      |> String.split(",")
      |> Enum.flat_map(&parse_period/1)
    end)
    |> Enum.sort_by(& &1.start, DateTime)
  end

  defp parse_period(period) do
    case String.split(String.trim(period), "/") do
      [start_s, end_or_duration] ->
        with {:ok, start_dt} <- parse_ics_instant(start_s),
             {:ok, end_dt} <- parse_period_end(start_dt, end_or_duration) do
          [%{start: start_dt, end: end_dt}]
        else
          _ -> []
        end

      _ ->
        []
    end
  end

  defp parse_period_end(start_dt, "P" <> _ = duration), do: add_ics_duration(start_dt, duration)
  defp parse_period_end(start_dt, "PT" <> _ = duration), do: add_ics_duration(start_dt, duration)
  defp parse_period_end(_start_dt, instant), do: parse_ics_instant(instant)

  defp parse_ics_instant(s) do
    case Regex.run(~r/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/, String.trim(s)) do
      [_, y, mo, d, h, mi, sec] ->
        with {:ok, date} <- Date.new(int(y), int(mo), int(d)),
             {:ok, time} <- Time.new(int(h), int(mi), int(sec)) do
          DateTime.new(date, time, "Etc/UTC")
        end

      _ ->
        :error
    end
  end

  defp add_ics_duration(start_dt, duration) do
    case Regex.run(~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/, String.trim(duration)) do
      [_ | parts] ->
        [d, h, m, s] = Enum.map(parts ++ List.duplicate("", 4 - length(parts)), &int_or_zero/1)
        seconds = d * 86_400 + h * 3600 + m * 60 + s
        if seconds > 0, do: {:ok, DateTime.add(start_dt, seconds, :second)}, else: :error

      _ ->
        :error
    end
  end

  defp ics_instant(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y%m%dT%H%M%SZ")
  end

  defp day_start_utc(date, timezone) do
    case DateTime.new(date, ~T[00:00:00], timezone) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:gap, _b, a} -> DateTime.shift_zone!(a, "Etc/UTC")
      {:ambiguous, f, _s} -> DateTime.shift_zone!(f, "Etc/UTC")
    end
  end

  defp int(s), do: String.to_integer(s)

  defp int_or_zero(""), do: 0
  defp int_or_zero(nil), do: 0
  defp int_or_zero(s), do: String.to_integer(s)

  defp http_options do
    (Application.get_env(:romp_crm, :calendar_http_options) || []) ++
      [finch: RompCrm.Finch, receive_timeout: 30_000]
  end
end
