defmodule RompCrm.Ai.SchedulingPlaybookExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(raw) when is_binary(raw), do: call(system_extract(), raw)

  def extract_structured(body) when is_binary(body) do
    prompt = """
    Parse the contractor's SMS reply to a scheduling setup question about work hours and outreach style.

    Contractor reply:
    ---
    #{body}
    ---

    Return JSON only:
    {
      "structured": {
        "work_hours_summary": "<short human summary, e.g. Mon-Fri 8am-5pm>",
        "outreach_style": "ask" | "offer" | "offer_then_ask",
        "outreach_style_label": "<short label>"
      },
      "prefs_updates": {
        "workday_start": "HH:MM",
        "workday_end": "HH:MM",
        "work_days": [1-7],
        "customer_outreach_style": "ask" | "offer" | "offer_then_ask"
      }
    }

    work_days: Monday=1 through Sunday=7. Default Mon-Fri if unclear.
  """

    call(system_structured(), prompt)
  end

  def extract_playbook_update(body, context) when is_binary(body) do
    ctx_json =
      case Jason.encode(context) do
        {:ok, j} -> j
        _ -> "{}"
      end

    prompt = """
    The contractor is updating how the scheduling agent should behave.

    Current context:
    #{ctx_json}

    Contractor message:
    ---
    #{body}
    ---

    Return JSON only:
    {
      "prefs_updates": { optional scheduling prefs fields },
      "playbook_rules": [
        { "kind": "greeting_template"|"confirm_before_offer_slots"|"min_lead_days"|"scheduling_bias"|"customer_outreach_style"|"custom_instruction",
          "config": { ... },
          "source_text": "<verbatim contractor instruction>" }
      ],
      "scheduling_memories": [ { "topic": "...", "answer": "..." } ],
      "assistant_summary": "<short SMS confirmation>"
    }

    Map natural language to kinds:
    - Custom greeting script → greeting_template with config.template
    - Confirm before offering customer specific times → confirm_before_offer_slots enabled true
    - At least N days out → min_lead_days in prefs_updates AND playbook rule
    - Soonest/ASAP → scheduling_bias asap in prefs_updates
    - Free-form behavior → custom_instruction
    """

    call(system_extract(), prompt)
  end

  defp call(system, user_content) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-6")

      body = %{
        model: model,
        max_tokens: 4096,
        system: system,
        messages: [%{role: "user", content: user_content}]
      }

      headers = [
        {"content-type", "application/json"},
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ]

      case Finch.build(:post, @api, headers, Jason.encode!(body)) |> Finch.request(@finch) do
        {:ok, %{status: 200, body: resp}} ->
          parse_response(resp)

        {:ok, %{status: status, body: resp}} ->
          {:error, {:anthropic_http, status, resp}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_response(resp) do
    with {:ok, %{"content" => [%{"text" => text} | _]}} <- Jason.decode(resp),
         {:ok, map} <- Jason.decode(strip_fences(text)) do
      {:ok, map}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp strip_fences(text) do
    text
    |> String.trim()
    |> String.replace_prefix("```json", "")
    |> String.replace_prefix("```", "")
    |> String.replace_suffix("```", "")
    |> String.trim()
  end

  defp system_extract do
    """
    You extract scheduling configuration for a home-services CRM scheduling agent.
    Respond with one JSON object only — no markdown fences.
    """
  end

  defp system_structured do
    """
    You parse contractor SMS replies into structured scheduling setup fields.
    Respond with one JSON object only — no markdown fences.
    """
  end
end
