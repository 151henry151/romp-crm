defmodule RompCrm.SchedulingAgentTest.ErrorReply do
  @moduledoc false

  @doc "User-facing message when an AI extractor fails in the test workspace."
  def for_reason(reason)

  def for_reason({:anthropic_http, 529, _}) do
    "The AI service is busy right now. Wait a few seconds and send your message again — nothing was lost."
  end

  def for_reason({:anthropic_http, status, _}) when status in [500, 502, 503, 504, 529] do
    "The AI service is temporarily unavailable (#{status}). Try again in a moment."
  end

  def for_reason({:anthropic_http, status, _}) when is_integer(status) do
    "The AI assistant returned an error (#{status}). Try again or reset the test workspace."
  end

  def for_reason({:request, _}) do
    "Couldn't reach the AI service. Check your connection and try again."
  end

  def for_reason(:missing_api_key) do
    "Anthropic API key is not configured on this server — the test workspace needs it to simulate replies."
  end

  def for_reason(:invalid_json_from_model) do
    "Got an unreadable reply from the assistant. Please try sending that again."
  end

  def for_reason(_reason) do
    "Couldn't process that message in the test workspace. Try again in a moment."
  end
end
