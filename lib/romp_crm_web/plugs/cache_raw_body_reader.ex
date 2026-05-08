defmodule RompCrmWeb.CacheRawBodyReader do
  @moduledoc """
  Stores the raw request body in `conn.private[:raw_body]` for webhook signature
  verification while still allowing `Plug.Parsers` to decode JSON.
  """

  @doc false
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.put_private(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
