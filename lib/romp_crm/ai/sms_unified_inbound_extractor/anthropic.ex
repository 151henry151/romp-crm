defmodule RompCrm.Ai.SmsUnifiedInboundExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(
        raw_message,
        jobs_snapshot \\ [],
        open_te_snapshot \\ [],
        employees_snapshot \\ [],
        prior_turns \\ []
      )
      when is_binary(raw_message) and is_list(prior_turns) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      call_claude(
        api_key,
        model,
        raw_message,
        jobs_snapshot,
        open_te_snapshot,
        employees_snapshot,
        prior_turns
      )
    end
  end

  defp call_claude(
         api_key,
         model,
         raw_message,
         jobs_snapshot,
         open_te_snapshot,
         employees_snapshot,
         prior_turns
       ) do
    body = %{
      model: model,
      max_tokens: 8192,
      system: system_prompt(),
      messages: [
        %{
          role: "user",
          content:
            user_content(
              raw_message,
              jobs_snapshot,
              open_te_snapshot,
              employees_snapshot,
              prior_turns
            )
        }
      ]
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

  defp user_content(
         raw_message,
         jobs_snapshot,
         open_te_snapshot,
         employees_snapshot,
         prior_turns
       ) do
    jobs_json = encode_json(jobs_snapshot)
    open_json = encode_json(open_te_snapshot)
    emp_json = encode_json(employees_snapshot)

    thread_block = format_prior_turns(prior_turns)

    """
    Parse the **latest** inbound SMS for Romp CRM: job creates/updates, per-job time clock-in/out, and employee clock-in/out/lunch.

    #{thread_block}

    Latest inbound SMS only (extract operations from this message — use the thread above only for resolving references like "that job", "Bob", "those hours", pronouns, or corrections):

    ---
    #{raw_message}
    ---

    Existing CRM jobs (JSON array). Each object has integer `"id"` — authoritative; never invent ids.
    Jobs snapshot:
    ---
    #{jobs_json}
    ---

    Open job time entries (clocked in, not ended). Use for clock-out alignment.
    Open time entries snapshot:
    ---
    #{open_json}
    ---

    Employees (JSON array). Each has integer `"id"` and `"name"`. Optional open employee time context.
    Employees snapshot:
    ---
    #{emp_json}
    ---
    """
  end

  defp format_prior_turns([]) do
    """
    Prior SMS thread with this contractor phone: *(none stored yet — first message in thread)*

    ---
    """
  end

  defp format_prior_turns(turns) when is_list(turns) do
    lines =
      Enum.map(turns, fn {role, text} ->
        label = if role == :assistant, do: "Assistant", else: "Contractor"
        "#{label}: #{text}"
      end)

    body =
      lines
      |> Enum.join("\n")

    """
    Prior SMS thread with this contractor phone (oldest first — same numbers as below). Use this so follow-ups stay coherent (who did the work, which job was meant, time ranges you already confirmed).

    ---
    #{body}
    ---

    """
  end

  defp encode_json(data) do
    case Jason.encode(data) do
      {:ok, bin} -> bin
      {:error, _} -> "[]"
    end
  end

  defp system_prompt do
    today = Date.utc_today() |> Date.to_iso8601()

    """
    You extract structured operations for a plumbing/mechanical contractor from the **latest** inbound SMS.

    The user message may include a **prior SMS thread** (Contractor / Assistant lines) for the same phone number, then JSON snapshots: **jobs**, **open job time entries**, and **employees**, then the latest SMS.
    **Always** use the prior thread to resolve follow-ups: e.g. attributing hours to the correct **employee** or **job** when the latest message only says "That was Bob" or "same as before" or corrects a name. The thread is authoritative for "what we already established" in this chat.
    Use semantic judgment (typos, informal references, nicknames) to decide which snapshot **`id`** values apply — the same way you match jobs for updates. **Never** invent database ids; every `job_id` and `employee_id` must appear in the provided snapshots.

    Respond with **one JSON object only** (no markdown fences, no commentary).

    ## Output shape (always)
    {
      "assistant_sms": "<short SMS ≤480 chars to send back; past tense confirmations or one clarifying question>",
      "job_actions": [ ... ],
      "time_actions": [ ... ],
      "employee_actions": [ ... ],
      "reminder_actions": [ ... ]
    }

    Use **empty arrays** for domains that do not apply. If nothing can be applied safely, use empty arrays for all action arrays and set `assistant_sms` to a brief clarifying question (never leave `assistant_sms` null when you need human input).

    ---

    ## job_actions — same schema as standalone job SMS extraction

    Each element is one action object:

    **Create lead:** `"intent": "create"` plus `"job": { "client_name", "address", "phone", ... }`.

    **Update job:** `"intent": "update"`, `"job_id": <int from jobs snapshot>`, `"updates": { only changed fields }`.

    **Work items (tasks):** In **create** `job` or **update** `updates`, include `"work_items": [ { "title": "...", "scheduled_on": "YYYY-MM-DD" or null, "sort_order": 0 } ]` when the SMS lists multiple distinct tasks (e.g. dishwasher, sink leak, shower valve). Prefer separate work item rows instead of one long `work_description` when the message clearly enumerates tasks.

    **Job-level date:** `"scheduled_on": "YYYY-MM-DD"` on create/update for the overall job start or primary visit date when stated.

    **Materials:** `"materials": [ { "description": "...", "job_work_item_id": <int from snapshot work_items> or omit for whole job, "work_item_index": <0-based index in snapshot work_items list> } ]`. Materials tied to a work item also appear in the combined job list in the app.

    **Attach photo (MMS):** When the inbound message includes Twilio image URL(s) and the user is adding a picture to an existing job, include `"intent": "attach_photo"`, `"job_id": <int>`, `"media_url": "<exact URL from message>"` (or `"media_urls": [...]`), optional `"work_item_title": "<substring of a work item title>"` to attach to that line item.

    Optional fallback when you truly cannot pick an id: `"match"` + `"updates"` (same as job-only flow).

    Prefer **`job_id`** from the snapshot whenever one row is the clear semantic fit.

    ---

    ## reminder_actions — personal reminders for the texting user

    Each element:
    - `{ "intent": "schedule", "fire_at": "<ISO 8601 UTC or Z>", "body": "<short reminder text>", "job_id": <optional int from jobs snapshot>, "metadata": { ... } }`
    - Use when the contractor asks to be reminded later (e.g. "remind me Tuesday 11am to call Suzy"). Put the human-readable task in **`body`**. If a snapshot job clearly matches (same customer name), set **`job_id`**. Otherwise omit **`job_id`** and set metadata like `{ "no_customer_match": true, "suggested_name": "Suzy" }` when appropriate.

    Return `[]` when there is no reminder intent.

    ---

    ## time_actions — job time clock-in / clock-out only

    Each element:
    - **Clock in:** `{ "intent": "clock_in", "job_id": <int from jobs snapshot>, "started_at": "<ISO 8601 naive local wall time>" }`
    - **Clock out:** `{ "intent": "clock_out", "job_id": <int>, "ended_at": "<ISO 8601>" }`

    You must choose **`job_id`** by comparing the SMS to the jobs snapshot (and open time entries when clocking out). **Do not** use a separate `"match"` object — disambiguate using reasoning over the snapshot ids.

    Use today's date **`#{today}`** for times unless the message states otherwise ("8am" → `#{today}T08:00:00`, etc.).

    Return `[]` if the SMS has no job time-tracking intent.

    ---

    ## employee_actions — employee clock-in, clock-out, lunch

    Each element uses **`employee_id`** from the employees snapshot only:

    - **Clock in:** `{ "intent": "clock_in", "employee_id": <int>, "clocked_in_at": "<ISO 8601>" }`
    - **Clock out:** `{ "intent": "clock_out", "employee_id": <int>, "clocked_out_at": "<ISO 8601>" }`
    - **Lunch:** `{ "intent": "lunch", "employee_id": <int>, "lunch_start_at": "<ISO 8601>", "lunch_end_at": "<ISO 8601>" }`

    Pick **`employee_id`** by reading names and context in the SMS against the snapshot — **no** free-text name match fields.

    Return `[]` if there are no employee time intents.

    ---

    ## Combined guidance

    - One SMS may produce actions in more than one array.
    - **`assistant_sms`** should summarize everything you applied or ask one focused question if ambiguous.
    - **`reminder_actions`** are independent of job permissions; still require valid `fire_at` and `body` when used.
    """
  end
end
