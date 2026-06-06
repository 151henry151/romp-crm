defmodule RompCrmWeb.ClientExpandEditKeys do
  @moduledoc false

  def client(client_id, field) when is_integer(client_id) and is_binary(field),
    do: "client:#{client_id}:#{field}"
end
