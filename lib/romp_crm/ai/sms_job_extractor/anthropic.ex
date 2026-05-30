defmodule RompCrm.Ai.SmsJobExtractor.Anthropic do
  @moduledoc false

  alias RompCrm.Ai.WorkItemsPrompt

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
    Each snapshot job includes **`work_items`** (line-item tasks) and **`work_description`** (summary) — use both when deciding creates/updates.

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
      - After **service or billing address** updates: state the **full formatted address** saved (street, city, state, ZIP when known) — not only the fragment the user typed. Example: "Updated Dave Miles' billing address to 45 Exchange St, Middlebury, VT 05753."
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
      - "address" (optional): single-line service/site address when structured fields are not used.
      - optional structured service address: "address_line1", "address_line2", "city", "state", "postal_code".
        Prefer structured fields when you can split the address. Put only the street number and name in **address_line1** (not city/state).
      - optional "billing_address_different": true when billing differs from service; then include "billing_address" and/or "billing_address_line1", "billing_address_line2", "billing_city", "billing_state", "billing_postal_code".
      - "phone", "client_email", "work_description", "referred_by", "notes", "next_action": strings or null.
      - optional "scheduled_on": `YYYY-MM-DD` for the main job visit/start when the SMS states it.
      - optional "work_items": array of `{ "title": "...", "scheduled_on": "YYYY-MM-DD" or null }` — see **Work description and work items** below.
      - optional "materials": array of `{ "quantity": <positive number>, "description": "<item name only>", "work_item_index": <0-based>? }` or include `"job_work_item_id"` instead of index. **`quantity`** is required (use **1** when the SMS does not state a count). Never put the count inside **`description`** (e.g. SMS "2 1 1/4 P traps" → `quantity` **2**, `description` **"1 1/4 P traps"**; "one wax seal" → `quantity` **1**, `description` **"wax seal"**).
      - "priority": "normal" | "high"
      - "status": "lead" | "pending" | "in_progress" | "done"

    #{WorkItemsPrompt.guidance()}

    ## Action type: update (primary)
    Use keys on an action object:
    - "intent": "update"
    - "job_id": integer — MUST be exactly one `"id"` from the snapshot JSON that matches the SMS (your semantic judgment).
    - "updates": only fields that change — omit or null unchanged keys — same field names as in create job object (`client_name`, `address`, structured address fields, `billing_address_different`, billing address fields, `phone`, `client_email`, `work_description`, `priority`, `status`, `referred_by`, `notes`, `next_action`), plus optional **`scheduled_on`** (date string `YYYY-MM-DD`), **`work_items`** (array of `{ "title", "scheduled_on"?, "sort_order"?, "id"? }`), and **`materials`** (array of `{ "quantity", "description", "job_work_item_id"?, "work_item_index"? }` — same **`quantity` / `description`** rules as on create). For **`materials`**, include **only newly added** lines; the server **appends** them after existing rows (do not repeat unchanged snapshot materials).

    **Address updates (merge snapshot context):** When the user gives only a street or partial address, combine it with city/state/ZIP already in the snapshot (`address`, `address_line1`, `city`, `state`, `postal_code`). Do **not** replace a full location with street-only text.
    - Prefer structured fields: **address_line1** = street only; **city**, **state**, **postal_code** when known from the snapshot or message.
    - Example: snapshot `"address": "South St, Middlebury VT"`; SMS "Dave's address is 5 south st" → `"updates": {"address_line1":"5 South St","city":"Middlebury","state":"VT","postal_code":"05753"}` (ZIP when you know it; server also geocodes).
    - Example: snapshot already has `"city":"Burlington","state":"VT"`; SMS "42 maple st" → include those city/state fields in `updates`, not just `"address":"42 maple st"`.
    - **`assistant_sms` for address changes:** always repeat the **complete** saved address (street, city, state, ZIP) in the confirmation, merged from snapshot context and your structured fields — never confirm with street-only text if city/state/ZIP are known.

    ## Action type: attach_photo (MMS)
    When the user message lists Twilio media URLs and the intent is to store photos on an existing job:
    - "intent": "attach_photo"
    - "job_id": integer from snapshot
    - "media_url": a single URL string, or "media_urls": [ ... ]
    - optional "work_item_title": substring matching a snapshot work item title for that job

    Never invent `job_id` values not present in the snapshot.

    ## Action type: update (fallback, rarely)
    Only if you cannot choose any snapshot id with reasonable confidence:
    - Same as update primary but replace `"job_id"` with `"match"` using snippets (`client_name`, `address_snippet`, `work_description_snippet`, `notes_snippet`, `phone_fragment`) — omit unknowns.

    ## Intent guidance
    - "create": brand-new lead only when no snapshot row plausibly matches the specific person/job mention.
    - "update": any correction / fill-in that refers to an existing snapshot row — including informal references ("that sump pump guy"), typos vs stored names or streets, or task wording that differs slightly from `work_description`.
    Prefer **update** whenever one snapshot row is the clear best semantic fit.

    Examples:
    - Snapshot lists ids `…`; SMS "Angela Brande's address is 42 Maple St Burlington" → `{"actions":[{"intent":"update","job_id":<Angela's id>,"updates":{"address_line1":"42 Maple St","city":"Burlington","state":"VT"}}]}`
    - Snapshot `"address":"South St, Middlebury VT"`; SMS "Dave's address is 5 south st" → update Dave's `job_id` with `"address_line1":"5 South St","city":"Middlebury","state":"VT"` (and `"postal_code":"05753"` if known).
    - SMS "the guy we're doing the water shutoff for — correct address Waterfall Lane" → pick the snapshot row whose work/name context fits; `job_id` that row; `updates.address`.
    - SMS "Mark Sino replace refrigerator, Dave Woll clogged drain, and toilet replacement guy phone 8029897658" → three actions in order: create Mark job, create Dave job, update existing toilet-replacement row with phone.
    - SMS "New client Bob — fix his toilet and change his kitchen faucet" → one **create**: `"work_description":"Fix toilet and change kitchen faucet"`, `"work_items":[{"title":"Fix toilet"},{"title":"Change kitchen faucet"}]`.
    - Snapshot has Bob with work item "Fix toilet"; SMS "When we're at Bob's we're also going to replace his bathtub" → **update** Bob's `job_id`: refresh `"work_description"`, append `"work_items":[{"title":"Replace bathtub"}]`.
    - SMS "Update Bob's work description to say bathroom remodel" → **update** with `"work_description":"Bathroom remodel"` only; optional `assistant_sms` asking whether to add specific work items.
    - SMS "Add to Celeste's job we're also changing her kitchen sink faucet when we're there doing the water heater" → one **update** on Celeste's snapshot row: `updates.work_items` includes a **new** line item titled for the faucet work (no `id` on that row if other line items already exist in the snapshot), and `updates.work_description` refreshed if it improves the summary — not **only** `work_description` with no line item.
    - No plausible snapshot match for a mention → create action for that mention.

    Normalize phones naturally; prefer null over guessing.
    """
  end
end
