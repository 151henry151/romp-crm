defmodule RompCrm.Ai.SmsTimeExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"

  def extract(raw_message, jobs_snapshot \\ [], open_entries_snapshot \\ [])
      when is_binary(raw_message) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      call_claude(api_key, model, raw_message, jobs_snapshot, open_entries_snapshot)
    end
  end

  defp call_claude(api_key, model, raw_message, jobs_snapshot, open_entries_snapshot) do
    body = %{
      model: model,
      max_tokens: 2048,
      system: system_prompt(),
      messages: [
        %{role: "user", content: user_content(raw_message, jobs_snapshot, open_entries_snapshot)}
      ]
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

    case Jason.decode(cleaned) do
      {:ok, %{} = map} ->
        {:ok, map}

      _ ->
        case Regex.run(~r/\{[\s\S]*\}/, cleaned) do
          [json] ->
            case Jason.decode(json) do
              {:ok, %{} = map} -> {:ok, map}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp user_content(raw_message, jobs_snapshot, open_entries_snapshot) do
    jobs_json = encode_json(jobs_snapshot)
    open_json = encode_json(open_entries_snapshot)

    """
    Parse the following SMS for job time-tracking events (clock-in / clock-out).

    SMS text:
    ---
    #{raw_message}
    ---

    Existing CRM jobs (JSON array). Each has integer "id" as the authoritative key.
    Jobs snapshot:
    ---
    #{jobs_json}
    ---

    Currently open time entries (no clock-out yet). Use these to match clock-out messages.
    Open entries snapshot:
    ---
    #{open_json}
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
    You extract job time-tracking events from contractor SMS messages.

    The user message includes the live CRM jobs snapshot and currently open time entries.
    Use today's date (#{today}) when inferring dates unless the message specifies otherwise.
    Respond with a single JSON object only (no markdown, no commentary).

    ## Output shape
    {
      "assistant_sms": "<short confirmation or null if not time-related>",
      "actions": []
    }

    Return `"actions": []` and `"assistant_sms": null` when the SMS contains no time-tracking events.

    ## Action: clock_in
    The contractor arrived at or started work on a job.
    {
      "intent": "clock_in",
      "job_id": <integer from snapshot>,
      "started_at": "<ISO 8601 datetime, e.g. 2026-05-11T08:00:00>"
    }

    ## Action: clock_out
    The contractor left or finished work on a job.
    {
      "intent": "clock_out",
      "job_id": <integer from snapshot>,
      "ended_at": "<ISO 8601 datetime>"
    }

    If you cannot identify the job with confidence, use "match" instead of "job_id":
    { "intent": "clock_in", "match": {"client_name": "Angela"}, "started_at": "..." }

    ## Time inference
    - "8am" → T08:00:00, "2pm" → T14:00:00, "noon" → T12:00:00, "3:30" → T15:30:00
    - Use today's date (#{today}) unless otherwise stated.

    ## Examples
    SMS "started at Angela's at 8am" → clock_in for Angela's job, started_at = today T08:00:00
    SMS "left Dave's house at 2pm" → clock_out for Dave's job, ended_at = today T14:00:00
    SMS "Mark needs a call" → no time events → { "assistant_sms": null, "actions": [] }
    """
  end
end
