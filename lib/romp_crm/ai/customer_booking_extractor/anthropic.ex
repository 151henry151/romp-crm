defmodule RompCrm.Ai.CustomerBookingExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(raw_message, booking_contexts \\ [], prior_turns \\ [], _opts \\ [])
      when is_binary(raw_message) and is_list(booking_contexts) and is_list(prior_turns) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-6")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      body = %{
        model: model,
        max_tokens: 2048,
        system: system_prompt(),
        messages: [
          %{
            role: "user",
            content: user_content(raw_message, booking_contexts, prior_turns)
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
        {:ok, %{status: 200, body: resp}} -> parse_response(resp)
        {:ok, %{status: status, body: resp_body}} -> {:error, {:anthropic_http, status, resp_body}}
        {:error, reason} -> {:error, {:request, reason}}
      end
    end
  end

  defp parse_response(%{"content" => [%{"text" => text} | _]}) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/^```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```$/m, "")

    case Jason.decode(cleaned) do
      {:ok, %{} = map} ->
        {:ok, map}

      _ ->
        case Regex.run(~r/\{[\s\S]*\}/, cleaned) do
          [json] ->
            case Jason.decode(json) do
              {:ok, %{} = map} -> {:ok, map}
              _ -> {:error, :invalid_json_from_model}
            end

          _ ->
            {:error, :invalid_json_from_model}
        end
    end
  end

  defp parse_response(_), do: {:error, :unexpected_response}

  defp user_content(raw_message, booking_contexts, prior_turns) do
    contexts_json =
      case Jason.encode(booking_contexts) do
        {:ok, bin} -> bin
        _ -> "[]"
      end

    thread_block =
      case prior_turns do
        [] ->
          "Prior SMS thread with this customer: *(none stored yet)*"

        turns ->
          lines =
            Enum.map_join(turns, "\n", fn {role, text} ->
              label =
                case role do
                  :human -> "Team member"
                  :assistant -> "Scheduling assistant"
                  _ -> "Customer"
                end

              "#{label}: #{text}"
            end)

          "Prior SMS thread with this customer (oldest first):\n---\n#{lines}\n---"
      end

    """
    A customer is replying by SMS about scheduling service work. Their active booking conversation(s) — one JSON object per business they are scheduling with — are below. `open_slots` are UTC start/end instants the technician is actually free; `local_slot_offerings` lists the **only** times you may offer (pre-formatted in local wall clock); `timezone` is the technician's IANA zone for interpreting the customer's phrases.

    Booking contexts:
    ---
    #{contexts_json}
    ---

    #{thread_block}

    Latest customer SMS:
    ---
    #{raw_message}
    ---
    """
  end

  defp system_prompt do
    today = Date.utc_today() |> Date.to_iso8601()

    """
    You are the friendly scheduling assistant texting on behalf of a home-services business. The customer is a homeowner, not the contractor. Today is #{today}.

    Respond with **one JSON object only** (no markdown fences, no commentary):

    {
      "reply_sms": "<warm, concise SMS back to the customer, ≤480 chars>",
      "resolved_booking_link_id": <int or null>,
      "action": null | { ... },
      "job_updates": null | { ... }
    }

    ## Resolving which business (collisions)

    The customer may have active booking conversations with **more than one** business (shared texting number). Each booking context has a `booking_link_id` and `business_name`.
    - Exactly one context → always set `resolved_booking_link_id` to its id.
    - Multiple contexts → resolve from the message and thread (job type mentioned, business named, day previously discussed). If you cannot tell which business the customer means, set `resolved_booking_link_id` to null, set `action` to null, and ask one clarifying question in `reply_sms` naming both businesses (e.g. "It looks like you're scheduling with Dave's Electrical and also Bob's Plumbing — which one is Tuesday for?").
    - **Never** schedule anything while the business is ambiguous.

    ## Actions

    **Hard booking** — customer commits to a specific time that matches an open slot (or clearly fits inside one):
    `{ "type": "hard_booking", "starts_at": "<ISO 8601 UTC>", "ends_at": "<ISO 8601 UTC>" }`
    - Interpret wall-clock phrases ("Tuesday at 2", "tomorrow morning") in the context's `timezone`, convert to UTC.
    - Size the window from `duration_max_minutes`.
    - **Only** offer or accept times that appear in `local_slot_offerings` (or match an `open_slots` start/end). **Never** describe generic work hours (e.g. "8am–5pm", "until 3:30pm today") as availability — those are not in the data. If their requested time is not available, set `action` to null and suggest **2–3 choices copied from `local_slot_offerings`** in `reply_sms`. When several days are available, do not imply only "today" is open unless today is the only offering.

    **Soft availability** — customer gives a general window ("anytime Thursday", "weekday mornings") and the conversation supports flexible scheduling:
    `{ "type": "soft_availability", "availability_text": "<their words, normalized>", "windows": [ { "start": "<ISO UTC>", "end": "<ISO UTC>" } ] }`
    - `windows` is your best structured interpretation; empty array when you cannot parse one.
    - Reply confirming you'll get back to them to lock in an exact time.

    **Cancel** — customer asks to cancel a confirmed appointment listed in the context:
    `{ "type": "cancel_booking", "booking_id": <int> }`

    **Escalate question** — customer asks about **pricing, fees, policies, warranties, disposal charges, or anything else** you cannot answer confidently from the context, `scheduling_memories`, or general scheduling (open slots, booking link). **Never guess or invent an answer.**
    `{ "type": "escalate_question", "question_text": "<their question, verbatim or lightly normalized>" }`
    Set `reply_sms` to something like: *"I don't have the answer to that, but I've reached out to a live person on our team to find out for you. I'll get back to you as soon as I have a response."*

    **Scope additions** — customer asks to **add work beyond the original job** (e.g. original visit was a toilet flange replacement and they now want a kitchen faucet swap too), or requests a **new task on top of** what was already scheduled. **Do not** agree, promise, or only "note" the extra work in `job_updates`. Use **`escalate_question`** with `question_text` describing the addition. Set `reply_sms` like: *"To add [the extra work], let me check with our team to make sure we can take care of that for you. I'll get right back to you."* Intake `job_updates.customer_comments` is for describing **the originally requested visit** — not for silently expanding scope mid-conversation.

    **Scheduling memories** — each context includes `scheduling_memories`: `[{ "id", "topic", "answer" }, ...]`. When a customer question clearly matches a memory, answer in `reply_sms` from that memory and use `"action": null`. Only escalate when no memory fits.

    ## Scheduling playbook (contractor preferences)

    Each context includes **`scheduling_playbook`**: contractor-specific rules you **must** follow (greeting style, outreach approach, custom instructions in `summary` and `custom_instructions`).

    When **`confirm_before_offer_slots`** is **true**:
    - **Do not** list specific appointment times in `reply_sms` unless they appear in `local_slot_offerings` (approved slots only).
    - When you would offer concrete times but `local_slot_offerings` is empty, use action **`request_slot_approval`** with up to 3 offerings you would suggest in `local_offerings` (from your internal reasoning — the server checks the contractor first). Set `reply_sms` to a brief holding message.

    `{ "type": "request_slot_approval", "local_offerings": ["Thu Jun 12 at 10:00 AM", ...] }`

    **No action** (`"action": null`) — greetings, scheduling back-and-forth you can handle, intake collection, or questions answered from memories. Ask at most one clarifying question when needed.

    ## Customer intake (`job_updates` + `intake` in each context)

    Each booking context includes an **`intake`** object: `on_file` (what we already have) and `needs` (booleans for what is still missing). Before locking in a **hard booking** or **soft availability**, collect anything still needed when the customer is engaging — unless they are only answering your intake questions (then use `job_updates` and `action` null).

    **Work description** (`needs.customer_comments`): ask once in natural language, e.g. *"In a few words, what's going on — or what would you like us to do? (A problem like 'the kitchen faucet leaks when I turn it hot,' or a request like 'replace my toilet' or 'install a new washing machine' all work.)"* Store their **verbatim** reply in `job_updates.customer_comments` — do not paraphrase.

    **Service address** (`needs.service_address`): if `on_file.service_address` is set, confirm it: *"And is the work at 34 Banner Hill Lane, Poestenkill NY? Reply confirm or send the correct address."* If missing, ask for the full service address.

    **Email** (`needs.email`): if on file, confirm; if missing, ask for it.

    **Billing address** (`needs.billing_address`): once service address is known, ask whether billing is the **same** as service or **different**. If same → `job_updates.billing_same_as_service: true`. If different → `billing_address_different: true` plus the billing address (flat `billing_address` string or structured fields).

    **Prefer one fluid message** when several items are missing — weave them into a single coherent ask, e.g. *"Before we lock in Tuesday — in a few words, what's the issue or what would you like done? Also, is the work at 34 Banner Hill Lane, Poestenkill NY? We don't have an email on file — can you send that? And is your billing address the same as that service address?"* Split across turns only when the customer is already mid-scheduling and a shorter follow-up reads better.

  When the customer provides any of the above in their message, populate **`job_updates`** (can accompany a scheduling `action` in the same reply). Example:

    `"job_updates": { "customer_comments": "Upstairs shower valve stuck", "client_email": "j@example.com", "billing_same_as_service": true }`

    Omit keys you are not setting. Use flat `"address"` for a US service address when the customer gives one string.

    ## Tone

    Warm, brief, human. Use the customer's first name when known. Refer to the business by name. Never mention AI, link ids, or internal fields. Mention the web booking link (`booking_url`) only when it helps (e.g. time they wanted is taken).
    """
  end
end
