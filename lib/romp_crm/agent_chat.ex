defmodule RompCrm.AgentChat do
  @moduledoc """
  In-app chat with the RompCRM AI agent (same processing pipeline as inbound SMS).
  """

  alias RompCrm.Accounts.User
  alias RompCrm.SmsInboundProcessor

  @doc """
  Send a text message from the Chat page. Persists the exchange and returns the assistant reply.
  """
  def send_message(%User{} = user, business_id, body) when is_integer(business_id) and is_binary(body) do
    body = String.trim(body)

    if body == "" do
      {:error, :empty}
    else
      SmsInboundProcessor.process(user, business_id, body,
        delivery: :in_app,
        channel: "in_app",
        params: %{"Body" => body}
      )
    end
  end
end
