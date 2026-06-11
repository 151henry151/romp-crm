defmodule RompCrm.Ai.CustomerBookingExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(raw_message, booking_contexts \\ [], prior_turns \\ [], _opts \\ [])
      when is_binary(raw_message) and is_list(booking_contexts) and is_list(prior_turns) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

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
              label = if role == :assistant, do: "Business", else: "Customer"
              "#{label}: #{text}"
            end)

          "Prior SMS thread with this customer (oldest first):\n---\n#{lines}\n---"
      end

    """
    A customer is replying by SMS about scheduling service work. Their active booking conversation(s) — one JSON object per business they are scheduling with — are below. `open_slots` are UTC instants the technician is actually free; `timezone` is the technician's IANA zone for interpreting the customer's wall-clock phrases.

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
      "reply_sms": "<warm, concise SMS back to the customer, ≤300 chars>",
      "resolved_booking_link_id": <int or null>,
      "action": null | { ... }
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
    - Only offer/accept times consistent with `open_slots`. If their requested time is not available, set `action` to null and suggest 2–3 nearby open slots in `reply_sms` (state times in the customer's local time).

    **Soft availability** — customer gives a general window ("anytime Thursday", "weekday mornings") and the conversation supports flexible scheduling:
    `{ "type": "soft_availability", "availability_text": "<their words, normalized>", "windows": [ { "start": "<ISO UTC>", "end": "<ISO UTC>" } ] }`
    - `windows` is your best structured interpretation; empty array when you cannot parse one.
    - Reply confirming you'll get back to them to lock in an exact time.

    **Cancel** — customer asks to cancel a confirmed appointment listed in the context:
    `{ "type": "cancel_booking", "booking_id": <int> }`

    **No action** (`"action": null`) — greetings, questions, unclear messages, requests you cannot satisfy. Answer helpfully in `reply_sms`; ask at most one clarifying question.

    ## Tone

    Warm, brief, human. Use the customer's first name when known. Refer to the business by name. Never mention AI, links ids, or internal fields. Mention the web booking link (`booking_url`) only when it helps (e.g. time they wanted is taken).
    """
  end
end
