defmodule JgsCrm.Ai.SmsJobExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"

  def extract(raw_message) when is_binary(raw_message) do
    api_key = Application.get_env(:jgs_crm, :anthropic_api_key)
    model = Application.get_env(:jgs_crm, :anthropic_model, "claude-sonnet-4-20250514")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      call_claude(api_key, model, raw_message)
    end
  end

  defp call_claude(api_key, model, raw_message) do
    body = %{
      model: model,
      max_tokens: 4096,
      system: system_prompt(),
      messages: [%{role: "user", content: user_content(raw_message)}]
    }

    case Req.post(@api,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           json: body,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: resp}} ->
        parse_claude_response(resp)

      {:ok, %{status: status, body: body}} ->
        {:error, {:anthropic_http, status, body}}

      {:error, reason} ->
        {:error, {:request, reason}}
    end
  end

  defp parse_claude_response(%{"content" => [%{"text" => text} | _]}) do
    case extract_json_object(text) do
      {:ok, map} -> {:ok, map}
      :error -> {:error, :invalid_json_from_model}
    end
  end

  defp parse_claude_response(_), do: {:error, :unexpected_response}

  defp extract_json_object(text) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/^```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```$/m, "")

    case try_decode_json(cleaned) do
      {:ok, map} ->
        {:ok, map}

      :error ->
        case Regex.run(~r/\{[\s\S]*\}/, cleaned) do
          [json] -> try_decode_json(json)
          _ -> :error
        end
    end
  end

  defp try_decode_json(str) do
    case Jason.decode(str) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> :error
    end
  end

  defp user_content(raw_message) do
    """
    Parse the following SMS or MMS text message into CRM fields. The message may be messy, abbreviated, or in any style.

    SMS text:
    ---
    #{raw_message}
    ---
    """
  end

  defp system_prompt do
    """
    You extract structured job leads for a plumbing/mechanical contractor CRM.

    Respond with a single JSON object only (no markdown fences, no commentary). Use these string keys:
    - "client_name" (required): person or business name for the customer.
    - "address": street address if present, else null.
    - "phone": phone number if present, else null.
    - "work_description": what work is needed in concise plain language, else null.
    - "priority": either "normal" or "high" based on urgency implied in the message; default "normal".
    - "status": one of "lead", "pending", "in_progress", "done". New inbound texts are usually "lead" unless clearly otherwise.
    - "referred_by": referral source if mentioned, else null.
    - "next_action": suggested next step with rough timing if mentioned (e.g. "Visit Thu May 7", "Call to schedule"), else null.
    - "notes": timing of call, pronunciation hints, availability, "works from home", or other meta detail that does not fit other fields; else null.

    Infer reasonably from context. Prefer null over guessing obscure fields. Normalize phone to digits with optional punctuation as given.
    """
  end
end
