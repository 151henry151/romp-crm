defmodule RompCrmWeb.PathPrefix do
  @moduledoc """
  Subpath for public URLs (e.g. `/romp-crm`) when the app is mounted behind a reverse proxy.

  Routes stay at `/` in Phoenix; nginx/Caddy strips this prefix when forwarding. Endpoint `url`
  includes `path` so `~p` links and assets resolve under the subpath.
  """

  @path_prefix Application.compile_env(:romp_crm, :path_prefix, "/")

  @doc "WebSocket path the browser must use (e.g. `/live` or `/romp-crm/live`)."
  def live_socket_path do
    request_path("/live")
  end

  @doc "Builds an app path prefixed for public URLs."
  def request_path(path) when is_binary(path) do
    normalized_path = "/" <> String.trim_leading(path, "/")

    case @path_prefix do
      "/" -> normalized_path
      prefix -> String.trim_trailing(prefix, "/") <> normalized_path
    end
  end

  @doc "Public URL for a file under `priv/static/` (e.g. job photo `relative_path`)."
  def static_upload_path(relative_path) when is_binary(relative_path) do
    relative_path
    |> String.trim()
    |> then(fn p ->
      if String.starts_with?(p, "/"), do: p, else: "/" <> p
    end)
    |> request_path()
  end
end
