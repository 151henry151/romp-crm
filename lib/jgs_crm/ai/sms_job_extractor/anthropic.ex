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
    You extract structured CRM updates for a plumbing/mechanical contractor from inbound SMS.

    Respond with a single JSON object only (no markdown fences, no commentary).

    ## intent
    - "create": brand-new lead / new job mention with no clear reference to an existing customer row.
    - "update": the message corrects or adds detail for someone already in the CRM (possessive like "Angela Brande's address is …", "the customer at 123 Oak …", "the bathroom remodel job — their name is …", nicknames, "that Castleton job", partial addresses, etc.).

    When unsure, prefer "create" only if there is truly no identifiable existing entity; otherwise "update" with strong match hints.

    ## Shape A — create
    Use keys:
    - "intent": "create"
    - "job": object with:
      - "client_name" (required): person or business name for the customer (never null for creates).
      - "address", "phone", "work_description", "referred_by", "notes", "next_action": strings or null.
      - "priority": "normal" | "high"
      - "status": "lead" | "pending" | "in_progress" | "done"

    ## Shape B — update
    Use keys:
    - "intent": "update"
    - "match": clues to find ONE existing job (include every clue the SMS gives; omit unknowns):
      - "client_name": full or partial customer name as stated.
      - "address_snippet": distinctive fragment of their property address (street number, road name, town).
      - "work_description_snippet": distinctive fragment of work mentioned (e.g. "basement", "bathroom remodel", "sump pump").
      - "notes_snippet": fragment matching internal notes if helpful.
      - "phone_fragment": last 4 digits or full normalized phone fragment if given.
    - "updates": only fields that change — each key optional; omit or null means leave unchanged:
      same names as job fields: "client_name", "address", "phone", "work_description", "priority", "status",
      "referred_by", "notes", "next_action".

    Examples:
    - "Angela Brande's address is 42 Maple St Burlington" → intent update; match client_name "Angela Brande"; updates address "42 Maple St Burlington".
    - "The customer at 32 Seminary St is Bob Sinclair now" → intent update; match address_snippet "32 Seminary"; updates client_name "Bob Sinclair".
    - "New caller Jane 802-555-0101 needs water heater" → intent create with job object.

    Normalize phones naturally; prefer null over guessing.
    """
  end
end
