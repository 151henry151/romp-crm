defmodule RompCrm.Ai.BookingEscalationExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(raw_message, escalations \\ [], prior_turns \\ [], _opts \\ [])
      when is_binary(raw_message) and is_list(escalations) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      body = %{
        model: model,
        max_tokens: 1024,
        system: system_prompt(),
        messages: [
          %{
            role: "user",
            content: user_content(raw_message, escalations, prior_turns)
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
             receive_timeout: 60_000
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
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, :invalid_json_from_model}
    end
  end

  defp parse_response(_), do: {:error, :unexpected_response}

  defp user_content(raw_message, escalations, prior_turns) do
    esc_json =
      case Jason.encode(escalations) do
        {:ok, bin} -> bin
        _ -> "[]"
      end

    thread =
      case prior_turns do
        [] -> "(none)"
        turns -> Enum.map_join(turns, "\n", fn {role, t} -> "#{role}: #{t}" end)
      end

    """
    Open booking escalations (JSON):
    ---
    #{esc_json}
    ---

    Prior contractor SMS thread:
    ---
    #{thread}
    ---

    Latest contractor SMS:
    ---
    #{raw_message}
    ---
    """
  end

  defp system_prompt do
    """
    You interpret SMS from a **contractor** (business owner) who may be replying about a **client scheduling question** the agent could not answer.

    Return one JSON object only:

    {
      "reply_sms": "<brief SMS back to the contractor>",
      "resolved_escalation_id": <int or null>,
      "intent": "<one of: not_escalation | contractor_handling | provide_answer | memory_decision | complete_with_answer>",
      "contractor_answer": "<optional — client's answer text when providing pricing/policy info>",
      "memory_summary": "<optional short memory label, e.g. 'Washing machine disposal costs $35'>",
      "save_memory": <true | false | null>
    }

    **not_escalation** — message is normal CRM work (jobs, time, booking confirm, etc.), not about an open escalation.

    **contractor_handling** — contractor will contact the client directly (e.g. "I'll call her", "I'll reach out").

    **provide_answer** — escalation status `pending_contractor`; contractor gives the answer to relay. Set `contractor_answer`. In `reply_sms`, confirm you'll tell the client and ask whether to **remember** this for similar future questions (one short yes/no question). Do **not** claim you already told the client.

    **memory_decision** — escalation status `pending_memory_confirm`; contractor answers yes/no about saving a memory. Set `save_memory` true/false.

    **complete_with_answer** — contractor gives the answer **and** memory yes/no in one message (e.g. "$35 for disposal, and yes remember that"). Set `contractor_answer`, `save_memory`, and optional `memory_summary`.

    When multiple escalations are open, set `resolved_escalation_id` from context; if unclear, use `not_escalation` and ask which client in `reply_sms`.
    """
  end
end
