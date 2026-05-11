defmodule RompCrm.Ai.SmsJobExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(raw_message, jobs_snapshot \\ [])
      when is_binary(raw_message) and is_list(jobs_snapshot) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      call_claude(api_key, model, raw_message, jobs_snapshot)
    end
  end

  defp call_claude(api_key, model, raw_message, jobs_snapshot) do
    body = %{
      model: model,
      max_tokens: 4096,
      system: system_prompt(),
      messages: [%{role: "user", content: user_content(raw_message, jobs_snapshot)}]
    }

    case Req.post(@api,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           json: body,
           finch: @finch,
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

  defp user_content(raw_message, jobs_snapshot) do
    jobs_json =
      case Jason.encode(jobs_snapshot) do
        {:ok, bin} -> bin
        {:error, _} -> "[]"
      end

    """
    Parse the following SMS or MMS text message into CRM fields. The message may be messy, abbreviated, misspelled, or informal.

    SMS text:
    ---
    #{raw_message}
    ---

    Existing CRM jobs (JSON array). Each object includes integer `"id"` — this is the database primary key and is authoritative.

    Compare the SMS to these rows. Use fuzzy judgment: typos, nicknames, "the guy", "that water shutoff job", partial addresses, etc.

    Jobs snapshot:
    ---
    #{jobs_json}
    ---
    """
  end

  defp system_prompt do
    """
    You extract structured CRM updates for a plumbing/mechanical contractor from inbound SMS.

    The user message includes the live CRM snapshot JSON plus the SMS. Respond with a single JSON object only (no markdown fences, no commentary).

    ## Output shape
    Always return a JSON object with:
    - `"assistant_sms"`: **required** — short SMS (≤300 chars) you will send back to the contractor:
      - After applying updates/creates: past tense confirmation ("Got it—updated Liz Farley's phone and added a note on Mark Miles.").
      - If you **cannot** safely choose a job or parse intent: ask one clear question (see clarification rules below).
      - If `"actions"` is empty because you need clarification, `assistant_sms` **must** be that question (never empty).
    - `"actions"`: array of action objects in message order (may be **empty** only when `assistant_sms` asks for clarification and you perform **no** database changes).

    If there is exactly one action you may either return:
    - top-level single action object (legacy shape, plus `assistant_sms`), OR
    - `"actions": [ ... ]`.
    Prefer `"actions"` for consistency.

    ## Clarification (no DB changes)
    When two or more snapshot jobs could match (e.g. same type of work for different clients), or the SMS is too vague:
    - Return `"actions": []` and set `assistant_sms` to a brief question naming the candidates when possible
      (example: "Two jobs match \"toilet supply lines\"—Max Jimbob or Dave Stevens—which phone should I update?").

    ## Action type: create
    Use keys on an action object:
    - "intent": "create"
    - "job": object with:
      - "client_name" (required): person or business name for the customer (never null for creates).
      - "address", "phone", "work_description", "referred_by", "notes", "next_action": strings or null.
      - "priority": "normal" | "high"
      - "status": "lead" | "pending" | "in_progress" | "done"

    ## Action type: update (primary)
    Use keys on an action object:
    - "intent": "update"
    - "job_id": integer — MUST be exactly one `"id"` from the snapshot JSON that matches the SMS (your semantic judgment).
    - "updates": only fields that change — omit or null unchanged keys — same field names as in create job object (`client_name`, `address`, `phone`, `work_description`, `priority`, `status`, `referred_by`, `notes`, `next_action`).

    Never invent `job_id` values not present in the snapshot.

    ## Action type: update (fallback, rarely)
    Only if you cannot choose any snapshot id with reasonable confidence:
    - Same as update primary but replace `"job_id"` with `"match"` using snippets (`client_name`, `address_snippet`, `work_description_snippet`, `notes_snippet`, `phone_fragment`) — omit unknowns.

    ## Intent guidance
    - "create": brand-new lead only when no snapshot row plausibly matches the specific person/job mention.
    - "update": any correction / fill-in that refers to an existing snapshot row — including informal references ("that sump pump guy"), typos vs stored names or streets, or task wording that differs slightly from `work_description`.
    Prefer **update** whenever one snapshot row is the clear best semantic fit.

    Examples:
    - Snapshot lists ids `…`; SMS "Angela Brande's address is 42 Maple St Burlington" → `{"actions":[{"intent":"update","job_id":<Angela's id>,"updates":{"address":"42 Maple St Burlington"}}]}`
    - SMS "the guy we're doing the water shutoff for — correct address Waterfall Lane" → pick the snapshot row whose work/name context fits; `job_id` that row; `updates.address`.
    - SMS "Mark Sino replace refrigerator, Dave Woll clogged drain, and toilet replacement guy phone 8029897658" → three actions in order: create Mark job, create Dave job, update existing toilet-replacement row with phone.
    - No plausible snapshot match for a mention → create action for that mention.

    Normalize phones naturally; prefer null over guessing.
    """
  end
end
