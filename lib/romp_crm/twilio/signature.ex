defmodule RompCrm.Twilio.Signature do
  @moduledoc """
  Validates `X-Twilio-Signature` for `application/x-www-form-urlencoded` webhooks.

  See: https://www.twilio.com/docs/usage/security#validating-requests
  """

  import Plug.Conn

  @doc """
  Returns true if the request signature matches Twilio's HMAC-SHA1 for the given
  `auth_token` and public URL.

  `public_url` must be the exact webhook URL registered in Twilio (scheme, host,
  path, optional port, optional query), e.g. `https://example.com/webhooks/twilio/sms`.
  If omitted, the URL is derived from the connection (using `X-Forwarded-Proto` / Host when present).
  """
  def valid?(_conn, nil, _opts), do: false

  def valid?(conn, auth_token, opts) when is_binary(auth_token) do
    case get_req_header(conn, "x-twilio-signature") do
      [sig | _] when is_binary(sig) -> secure_compare?(conn, auth_token, sig, opts)
      _ -> false
    end
  end

  defp secure_compare?(conn, auth_token, signature, opts) do
    public_url =
      case Keyword.fetch(opts, :public_url) do
        {:ok, url} when is_binary(url) and url != "" -> url
        _ -> request_url_for_twilio(conn)
      end

    params = conn.body_params || %{}

    data = public_url <> sorted_param_string(params)

    expected =
      :crypto.mac(:hmac, :sha, auth_token, data)
      |> Base.encode64()

    Plug.Crypto.secure_compare(expected, signature)
  end

  defp sorted_param_string(params) when is_map(params) do
    params
    |> Map.to_list()
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map_join("", fn {k, v} -> to_string(k) <> param_value(v) end)
  end

  defp param_value(v) when is_binary(v), do: v
  defp param_value(v) when is_list(v), do: Enum.map_join(v, "", &param_value/1)
  defp param_value(v), do: to_string(v)

  def request_url_for_twilio(conn) do
    scheme = forwarded_scheme(conn) || to_string(conn.scheme)
    {host, parsed_port} = host_and_port(conn)
    port = parsed_port || conn.port
    path = conn.request_path
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

    port_part =
      case {scheme, port} do
        {"https", 443} -> ""
        {"http", 80} -> ""
        {_, p} when is_integer(p) -> ":#{p}"
        _ -> ""
      end

    scheme <> "://" <> host <> port_part <> path <> query
  end

  defp forwarded_scheme(conn) do
    case get_req_header(conn, "x-forwarded-proto") do
      [h | _] -> h
      _ -> nil
    end
  end

  defp host_and_port(conn) do
    case get_req_header(conn, "x-forwarded-host") do
      [h | _] -> parse_host_header(h)
      _ -> default_host_and_port(conn)
    end
  end

  defp default_host_and_port(conn) do
    case get_req_header(conn, "host") do
      [h | _] -> parse_host_header(h)
      _ -> {"localhost", conn.port}
    end
  end

  defp parse_host_header(h) do
    case String.split(h, ":", parts: 2) do
      [host, port_str] -> {host, String.to_integer(port_str)}
      [host] -> {host, nil}
    end
  end
end
