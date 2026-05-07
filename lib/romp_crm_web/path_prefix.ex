defmodule RompCrmWeb.PathPrefix do
  @moduledoc """
  Subpath for public URLs (e.g. `/romp-crm`) when the app is mounted behind a reverse proxy.

  Routes stay at `/` in Phoenix; nginx/Caddy strips this prefix when forwarding. Endpoint `url`
  includes `path` so `~p` links and assets resolve under the subpath.
  """

  @path_prefix Application.compile_env(:romp_crm, :path_prefix, "/")

  @doc "WebSocket path the browser must use (e.g. `/live` or `/romp-crm/live`)."
  def live_socket_path do
    case @path_prefix do
      "/" -> "/live"
      prefix -> String.trim_trailing(prefix, "/") <> "/live"
    end
  end
end
