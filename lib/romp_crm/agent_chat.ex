defmodule RompCrm.AgentChat do
  @moduledoc """
  In-app chat with the RompCRM AI agent (same processing pipeline as inbound SMS).
  """

  alias RompCrm.Accounts.User
  alias RompCrm.ChatMedia
  alias RompCrm.SmsInboundProcessor

  @doc """
  Send a text and/or image message from the Chat page. Persists the exchange and
  returns the assistant reply.

  Options:

    * `:media_urls` — public HTTPS URLs from **`ChatMedia.store!/3`** (fed to the
      unified extractor as MMS vision blocks)
  """
  def send_message(%User{} = user, business_id, body, opts \\ [])
      when is_integer(business_id) and is_binary(body) and is_list(opts) do
    body = String.trim(body)

    media_urls =
      opts
      |> Keyword.get(:media_urls, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(ChatMedia.max_images())

    cond do
      body == "" and media_urls == [] ->
        {:error, :empty}

      true ->
        params = twilio_style_params(body, media_urls)
        body_for_process = if body == "", do: "", else: body

        SmsInboundProcessor.process(user, business_id, body_for_process,
          delivery: :in_app,
          channel: "in_app",
          params: params
        )
    end
  end

  defp twilio_style_params(body, media_urls) do
    base = %{"Body" => body, "NumMedia" => Integer.to_string(length(media_urls))}

    media_urls
    |> Enum.with_index()
    |> Enum.reduce(base, fn {url, i}, acc -> Map.put(acc, "MediaUrl#{i}", url) end)
  end
end
