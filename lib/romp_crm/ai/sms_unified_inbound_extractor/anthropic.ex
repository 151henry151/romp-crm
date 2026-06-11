defmodule RompCrm.Ai.SmsUnifiedInboundExtractor.Anthropic do
  @moduledoc false

  alias RompCrm.Ai.WorkItemsPrompt

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(
        raw_message,
        jobs_snapshot \\ [],
        open_te_snapshot \\ [],
        employees_snapshot \\ [],
        prior_turns \\ [],
        opts \\ []
      )
      when is_binary(raw_message) and is_list(prior_turns) and is_list(opts) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      mms_image_blocks = Keyword.get(opts, :mms_image_blocks, [])
      recent_deleted_jobs = Keyword.get(opts, :recent_deleted_jobs, [])
      clients_snapshot = Keyword.get(opts, :clients_snapshot, [])
      bookings_snapshot = Keyword.get(opts, :bookings_snapshot, %{})

      call_claude(
        api_key,
        model,
        raw_message,
        jobs_snapshot,
        open_te_snapshot,
        employees_snapshot,
        prior_turns,
        mms_image_blocks,
        recent_deleted_jobs,
        clients_snapshot,
        bookings_snapshot
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
         prior_turns,
         mms_image_blocks,
         recent_deleted_jobs,
         clients_snapshot,
         bookings_snapshot
       ) do
    user_blocks =
      build_user_content_blocks(
        raw_message,
        jobs_snapshot,
        open_te_snapshot,
        employees_snapshot,
        prior_turns,
        mms_image_blocks,
        recent_deleted_jobs,
        clients_snapshot,
        bookings_snapshot
      )

    body = %{
      model: model,
      max_tokens: 8192,
      system: system_prompt(),
      messages: [
        %{
          role: "user",
          content: user_blocks
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

  defp build_user_content_blocks(
         raw_message,
         jobs_snapshot,
         open_te_snapshot,
         employees_snapshot,
         prior_turns,
         mms_image_blocks,
         recent_deleted_jobs,
         clients_snapshot,
         bookings_snapshot
       ) do
    text =
      user_content_text(
        raw_message,
        jobs_snapshot,
        open_te_snapshot,
        employees_snapshot,
        prior_turns,
        recent_deleted_jobs,
        clients_snapshot,
        bookings_snapshot
      )

    image_blocks =
      Enum.map(mms_image_blocks, fn %{media_type: mt, data: b64} ->
        %{
          type: "image",
          source: %{
            type: "base64",
            media_type: mt,
            data: b64
          }
        }
      end)

    image_blocks ++ [%{type: "text", text: text}]
  end

  defp user_content_text(
         raw_message,
         jobs_snapshot,
         open_te_snapshot,
         employees_snapshot,
         prior_turns,
         recent_deleted_jobs,
         clients_snapshot,
         bookings_snapshot
       ) do
    jobs_json = encode_json(jobs_snapshot)
    clients_json = encode_json(clients_snapshot)
    open_json = encode_json(open_te_snapshot)
    emp_json = encode_json(employees_snapshot)
    deleted_json = encode_json(recent_deleted_jobs)
    bookings_json = encode_json(bookings_snapshot)

    thread_block = format_prior_turns(prior_turns)

    deleted_block =
      if recent_deleted_jobs == [] do
        ""
      else
        """

        Recently deleted jobs (removed from CRM — **not** in the jobs snapshot below; do **not** update these **`job_id`** values; use **create** if the contractor asks for that customer again):
        ---
        #{deleted_json}
        ---
        """
      end

    """
    Parse the **latest** inbound SMS for Romp CRM: job creates/updates, per-job time clock-in/out, and employee clock-in/out/lunch.

    #{thread_block}

    Latest inbound SMS only (extract operations from this message — use the thread above only for resolving references like "that job", "Bob", "those hours", pronouns, or corrections):

    ---
    #{raw_message}
    ---

    Existing CRM jobs (JSON array). Each object has integer `"id"` — authoritative for **current** rows; never invent ids.
    Jobs snapshot:
    ---
    #{jobs_json}
    ---#{deleted_block}

    Existing CRM clients (JSON array). Each object has integer `"id"` — persistent contact records; jobs may link via `"client_id"`.
    Match inbound names/phones/addresses to these **before** creating duplicate clients. When several clients could match, ask in **`assistant_sms`** instead of guessing.
    Clients snapshot:
    ---
    #{clients_json}
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

    Customer scheduling state (JSON object): `"active_booking_links"` (booking conversations already started),
    `"pending_booking_requests"` (clients who texted soft availability, awaiting a confirmed time), and
    `"upcoming_bookings"` (confirmed appointments). Ids here are authoritative for `booking_actions`.
    Bookings snapshot:
    ---
    #{bookings_json}
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

    The user message may include a **prior SMS thread** (Contractor / Assistant lines) for the same phone number, then JSON snapshots: **clients**, **jobs**, **open job time entries**, and **employees**, then the latest SMS.
    **Always** use the prior thread to resolve follow-ups: e.g. attributing hours to the correct **employee** or **job** when the latest message only says "That was Bob" or "same as before" or corrects a name. The thread is authoritative for "what we already established" in this chat — **except** when a job id or name appears in **Recently deleted jobs**, treat that row as gone and prefer **create** or a still-present snapshot id.

    **Clients vs jobs:** **`clients`** are persistent contact records; **`jobs`** are work rows that may link to a client. When creating a job for a known customer, prefer matching a **`clients`** snapshot **`id`** and include **`"client_id": <int>`** on the create **`job`** object when the match is clear. When several client rows could match (same name, different addresses), use empty **`job_actions`** and ask one clarifying question in **`assistant_sms`**. When no client matches, omit **`client_id`** — the server creates a new client from contact fields.

    **Deleted jobs:** When **Recently deleted jobs** lists a **`job_id`**, that row no longer exists. Prior chat may still mention it; do **not** refuse a new **create** for the same client name or assume the old job is still open.
    Use semantic judgment (typos, informal references, nicknames) to decide which snapshot **`id`** values apply — the same way you match jobs for updates. **Never** invent database ids; every `job_id` and `employee_id` must appear in the provided snapshots.

    Respond with **one JSON object only** (no markdown fences, no commentary).

    ## Output shape (always)
    {
      "assistant_sms": "<short SMS ≤480 chars to send back; past tense confirmations or one clarifying question>",
      "image_kind": "<see MMS images section when photos attached>",
      "proposed_job_creates": [ ... ],
      "job_actions": [ ... ],
      "time_actions": [ ... ],
      "employee_actions": [ ... ],
      "reminder_actions": [ ... ],
      "booking_actions": [ ... ]
    }

    Use **empty arrays** for domains that do not apply. If nothing can be applied safely, use empty arrays for all action arrays and set `assistant_sms` to a brief clarifying question (never leave `assistant_sms` null when you need human input).

    **`image_kind`:** When MMS images are attached, set one of: `sms_screenshot`, `email_screenshot`, `handwritten_note`, `other`, or `none` (job-site / equipment photo, not readable correspondence). Omit or `none` when there are no images.

    **`proposed_job_creates`:** Array of proposed new leads/jobs from **readable correspondence** images only (see MMS images). Default `[]`.

    ---

    ## job_actions — same schema as standalone job SMS extraction

    Each element is one action object:

    **Create lead:** `"intent": "create"` plus `"job": { "client_name", "address", "phone", "client_email", optional "client_id", ... }`.
    When a **`clients`** snapshot row clearly matches, set **`"client_id"`** on the **`job`** object to that integer id (still include readable **`client_name`** / contact fields from the message).
    **New job rows:** When the user asks to create a new lead/job, always emit **create** — even if the same **client_name** was used before or appears in prior chat for a deleted job. Trust the **jobs snapshot** only; if no snapshot **`job_id`** fits, create a fresh row (duplicate client names across jobs are allowed).

    **Update job:** `"intent": "update"`, `"job_id": <int from jobs snapshot>`, `"updates": { only changed fields }`.

    #{WorkItemsPrompt.guidance()}

    **Job-level date:** `"scheduled_on": "YYYY-MM-DD"` on create/update for the overall job start or primary visit date when stated.

    **Materials:** each object must include **`quantity`** (a positive number; default **1**) and **`description`** (the **item name only** — never put the count inside `description`).
    Optional: `"job_work_item_id"` (int from snapshot `work_items`) or `"work_item_index"` (0-based index in snapshot `work_items`) to tie the line to a task; omit both for whole-job supplies.
    Examples: `{"quantity":2,"description":"1 1/4\\\" P traps"}`, `{"quantity":1,"description":"wax seal"}`, `{"quantity":2,"description":"1/2\\\" PRS 90s"}`.
    Spoken counts in the SMS (**two**, **one**, …) must become **`quantity`**, not a prefix inside **`description`**.
    On **job updates**, put **only newly added** material lines in **`updates.materials`** — the server **appends** them after existing rows. Do **not** repeat unchanged snapshot materials (that would duplicate lines).

    **Attach photo (MMS):** When the inbound message includes Twilio image URL(s) and the user is adding a picture to an existing job, include `"intent": "attach_photo"`, `"job_id": <int>`, `"media_url": "<exact URL from message>"` (or `"media_urls": [...]`), optional `"work_item_title": "<substring of a work item title>"` to attach to that line item.
    If the contractor is only answering **which job** photos belong to (text reply, no new images), attach each URL **once** — omit URLs you already attached to that `job_id` in this thread. When several jobs could match, use **empty** `job_actions` and ask one clarifying question in **`assistant_sms`** (do not attach until the job is clear).

    ---

    ## MMS images (screenshots, email, handwritten notes)

    When one or more **images** are attached to this message, **look at each image** before deciding actions.

    **Classify `image_kind`:**
    - `sms_screenshot` — phone text-message thread screenshot (iMessage, Android Messages, etc.)
    - `email_screenshot` — email app or inbox screenshot
    - `handwritten_note` — paper note, whiteboard, or photo of handwriting listing job(s)
    - `none` / `other` — job-site photo, part, meter reading, etc. (not primarily text correspondence)

    **When `image_kind` is `sms_screenshot`, `email_screenshot`, or `handwritten_note`:**
    1. Read **all** visible text (names, phone numbers, addresses, problem description, availability windows, email addresses).
    2. For **each distinct customer/job** you can identify, add one element to **`proposed_job_creates`** (do **not** put these in **`job_actions`** yet — the server waits for contractor confirmation):
       `{ "job": { "client_name", "address", "phone", "client_email", "work_description", "notes", "status": "lead" or "pending", "scheduled_on", "work_items": [...] }, "attach_media_urls": ["<each exact Twilio MediaUrl from the message, for every proposal>"] }`
    3. On SMS screenshots, use the **customer's** phone number shown in the thread (not the contractor's). Put availability / scheduling hints in **`notes`** if they do not map to **`scheduled_on`**.
    4. For a **handwritten note** with multiple leads, use **one `proposed_job_creates` entry per lead**; include the **same** `attach_media_urls` on **each** entry so the note image is stored on every created job after confirmation.
    5. Set **`assistant_sms`** to a concise **proposal** listing each lead (name, address, work, phone) and end with: **Reply CONFIRM to create these, or correct any field in a text.** Do **not** use past-tense "created" language.
    6. Keep **`job_actions`** empty except you may omit attach_photo until after confirmation (photos attach when they confirm).

    **When `image_kind` is `none` or `other`:** use normal **`attach_photo`** / job update rules; **`proposed_job_creates`** should be `[]`.

    Optional fallback when you truly cannot pick an id: `"match"` + `"updates"` (same as job-only flow).

    Prefer **`job_id`** from the snapshot whenever one row is the clear semantic fit.

    ---

    ## reminder_actions — personal reminders for the texting user

    Each element:
    - `{ "intent": "schedule", "fire_at": "<ISO 8601 instant>", "body": "<short reminder text>", "job_id": <optional int from jobs snapshot>, "metadata": { ... } }`
    - **`fire_at`:** Prefer UTC with **`Z`** or an explicit offset (e.g. `2026-05-08T19:30:00Z`). If you output a **naive** timestamp without zone (e.g. `2026-05-08T15:30:00`), the server treats it as **wall clock time in the user's SMS reminder profile time zone** (same IANA zone as Romp CRM → Settings → SMS reminders — Eastern, Central, etc.), then converts to UTC for storage — same convention as **`time_actions`** clock times.
    - Use when the contractor asks to be reminded later (e.g. "remind me Tuesday 11am to call Suzy"). Put the human-readable task in **`body`**. If a snapshot job clearly matches (same customer name), set **`job_id`**. Otherwise omit **`job_id`** and set metadata like `{ "no_customer_match": true, "suggested_name": "Suzy" }` when appropriate.

    Return `[]` when there is no reminder intent.

    ---

    ## booking_actions — customer self-scheduling conversations

    Use when the contractor asks the agent to **reach out to a customer to schedule work** ("Text Bob Smith at 802-530-0293 to schedule his toilet flange replacement", "Send Maria a booking message for the kitchen faucet job"), to adjust a booking estimate, to confirm a soft-availability window, or to cancel a booking. The **Bookings snapshot** in the user message lists active booking links, pending soft-availability requests, and upcoming bookings — its ids are the only valid ids here.

    Each element is one of:

    **Start a booking conversation:**
    `{ "intent": "initiate", "client_name": "<name>", "phone": "<customer phone from message or clients snapshot>", "client_id": <optional int from clients snapshot>, "job_id": <optional int from jobs snapshot>, "job_type_label": "<short job description, e.g. toilet flange replacement>", "duration_min_minutes": <int>, "duration_max_minutes": <int> }`

    **Estimate the duration yourself** from the job type using trade knowledge. Typical plumbing examples:
    - Toilet flange replacement → 120–180
    - Kitchen faucet replacement → 90–120
    - Water heater install → 180–240
    - Drain snake / clog → 60–60
    - Annual inspection → 60–60
    Scale similarly for other trades. The contractor can override later; if they state a duration, use theirs.
    Phone is **required** — if the contractor gave no phone and no clients-snapshot match has one, ask for it in **`assistant_sms`** with empty `booking_actions`. If the stated phone is **not a valid US number** (10 digits, or 11 starting with 1 — e.g. only 9 digits), do **not** emit `initiate`; ask the contractor to re-send the correct number in **`assistant_sms`** (you may still emit the `job_actions` create).
    The server sends the customer an SMS with a self-scheduling web link and an invitation to reply by text; do **not** draft that message yourself. Confirm in **`assistant_sms`** what you set up (job type + duration estimate).

    **Create + schedule in one message:** When the contractor gives a **customer name, phone, and work to do**, default to **both** a `job_actions` create **and** a `booking_actions` initiate — the server texts the customer to schedule unless the contractor clearly only wants a CRM lead saved (`"just add a lead"`, `"don't text them"`, `"save for later"`). Examples that need **both** ops: "Jasmine Blair wants me to fix her camping sink, her number is 802-734-9389"; "Bob Smith 802-530-0293 kitchen sink replacement — schedule with him"; "Maria needs a faucet replaced, 555-123-4567". On the initiate, omit `job_id`/`client_id` for the just-created lead — the server links the booking to the job and client created by this same message (matched by phone), never duplicating the client.

    **Edit a duration estimate:** `{ "intent": "update_duration", "booking_link_id": <int from active_booking_links>, "duration_min_minutes": <int>, "duration_max_minutes": <int> }`

    **Confirm a soft-availability request at a specific time:** `{ "intent": "confirm_soft", "booking_request_id": <int from pending_booking_requests>, "starts_at": "<ISO 8601>", "ends_at": "<ISO 8601>" }` — e.g. contractor says "Book Bob for Thursday at 10". Naive timestamps are wall-clock in the user's reminder timezone. Size `ends_at` from the booking's duration estimate.

    **Cancel:** `{ "intent": "cancel", "booking_id": <int from upcoming_bookings>, "reason": "<optional short reason>" }`

    Return `[]` only when the message has **no** customer-scheduling intent **and** the contractor did **not** just supply name + phone + work for a new customer (see create + schedule default above).

    ---

    ## time_actions — job time clock-in / clock-out only

    Each element:
    - **Clock in:** `{ "intent": "clock_in", "job_id": <int from jobs snapshot>, "started_at": "<ISO 8601 naive local wall time>" }`
    - **Clock out:** `{ "intent": "clock_out", "job_id": <int>, "ended_at": "<ISO 8601>" }`

    You must choose **`job_id`** by comparing the SMS to the jobs snapshot (and open time entries when clocking out). **Do not** use a separate `"match"` object — disambiguate using reasoning over the snapshot ids.

    Use today's date **`#{today}`** for times unless the message states otherwise ("8am" → `#{today}T08:00:00`, etc.).

    Return `[]` if the SMS has no job time-tracking intent.

    ---

    ## employee_actions — workday timeclock (not job/client hours)

    Each element uses **`employee_id`** from the employees snapshot. Use **`open_entry`** on that employee for clock_out/lunch; use **`recent_entries`** (with `entry_id`) for corrections.

    - **Clock in:** `{ "intent": "clock_in", "employee_id": <int>, "clocked_in_at": "<ISO 8601>" }` — e.g. "Bob arrived 8am"
    - **Clock out:** `{ "intent": "clock_out", "employee_id": <int>, "clocked_out_at": "<ISO 8601>" }` — closes the open entry; e.g. "Bob left at 4pm"
    - **Lunch:** `{ "intent": "lunch", "employee_id": <int>, "lunch_start_at": "...", "lunch_end_at": "..." }` — requires open entry
    - **Log shift:** `{ "intent": "log_shift", "employee_id": <int>, "clocked_in_at": "...", "clocked_out_at": "...", optional lunch fields }` — both times in one message, e.g. "Bob worked 8am-4pm today"
    - **Adjust entry:** `{ "intent": "adjust_entry", "entry_id": <int from recent_entries>, "employee_id": <int>, only changed time fields }`

    **Disambiguation:** If the SMS is about hours on a **specific client job** (snapshot job name/address context), use **`time_actions`** instead, not `employee_actions`. If unclear, ask one short question in **`assistant_sms`**.

    Return `[]` if there are no employee workday intents.

    ---

    ## Combined guidance

    - One SMS may produce actions in more than one array.
    - **`assistant_sms`** should summarize everything you applied or ask one focused question if ambiguous.
    - After **service or billing address** updates, **`assistant_sms`** must state the **full formatted address** (street, city, state, ZIP when known), not only what the user typed — e.g. "Updated Dave Miles' billing address to 45 Exchange St, Middlebury, VT 05753."
    - **`reminder_actions`** are independent of job permissions; still require valid `fire_at` and `body` when used.
    """
  end
end
