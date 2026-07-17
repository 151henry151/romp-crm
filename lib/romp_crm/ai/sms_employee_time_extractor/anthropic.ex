defmodule RompCrm.Ai.SmsEmployeeTimeExtractor.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def extract(raw_message, employees_snapshot \\ []) when is_binary(raw_message) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-6")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      call_claude(api_key, model, raw_message, employees_snapshot)
    end
  end

  defp call_claude(api_key, model, raw_message, employees_snapshot) do
    body = %{
      model: model,
      max_tokens: 2048,
      system: system_prompt(),
      messages: [%{role: "user", content: user_content(raw_message, employees_snapshot)}]
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

  defp user_content(raw_message, employees_snapshot) do
    emp_json =
      case Jason.encode(employees_snapshot) do
        {:ok, bin} -> bin
        {:error, _} -> "[]"
      end

    """
    Parse the following SMS for employee time-tracking events.

    SMS text:
    ---
    #{raw_message}
    ---

    Employee list (JSON array). Each has integer "id" and "name". The "open_entry" field
    shows the current active clock-in for that employee if one exists.

    Employees snapshot:
    ---
    #{emp_json}
    ---
    """
  end

  defp system_prompt do
    today = Date.utc_today() |> Date.to_iso8601()

    """
    You extract employee time-tracking events from contractor SMS messages.

    The user is a contractor who tracks when employees clock in, clock out, and take lunch.
    Respond with a single JSON object only (no markdown, no commentary).

    ## Output shape
    {
      "assistant_sms": "<short confirmation or null if not employee-time-related>",
      "actions": []
    }

    Return `"actions": []` and `"assistant_sms": null` when the SMS contains no employee time events.

    ## Action: clock_in  (employee starts work)
    Triggered by: "picked Henry up", "Henry clocked in", "Henry started at 8am", etc.
    {
      "intent": "clock_in",
      "employee_id": <integer from snapshot>,
      "clocked_in_at": "<ISO 8601 datetime>"
    }

    ## Action: clock_out  (employee ends work)
    Triggered by: "dropped Henry off", "Henry clocked out", "Henry done at 4pm", etc.
    {
      "intent": "clock_out",
      "employee_id": <integer from snapshot>,
      "clocked_out_at": "<ISO 8601 datetime>"
    }

    ## Action: lunch  (employee takes lunch break)
    Triggered by: "Henry took lunch from noon to 1pm", "Henry lunch 12-1", etc.
    Requires an **open** clock-in on the snapshot for that employee.
    {
      "intent": "lunch",
      "employee_id": <integer from snapshot>,
      "lunch_start_at": "<ISO 8601 datetime>",
      "lunch_end_at": "<ISO 8601 datetime>"
    }

    ## Action: log_shift  (record a full workday in one message)
    Triggered by: "Bob worked from 8am to 4pm today", "Henry 7:30-3:30", etc.
    Use when both start and end are stated (or implied) in one message — **not** job/client hours.
    {
      "intent": "log_shift",
      "employee_id": <integer>,
      "clocked_in_at": "<ISO 8601>",
      "clocked_out_at": "<ISO 8601>",
      "lunch_start_at": "<optional ISO 8601>",
      "lunch_end_at": "<optional ISO 8601>"
    }

    ## Action: adjust_entry  (correct a past closed entry)
    Use `entry_id` from the employee snapshot `recent_entries` list.
    {
      "intent": "adjust_entry",
      "entry_id": <integer>,
      "employee_id": <integer>,
      "clocked_in_at": "<optional ISO 8601>",
      "clocked_out_at": "<optional ISO 8601>",
      "lunch_start_at": "<optional>",
      "lunch_end_at": "<optional>",
      "notes": "<optional string>"
    }

    ## Workday vs job time
    - **Employee workday** (this extractor): shop/yard clock, "Bob clocked in", "Bob worked 8-4", arrivals/departures.
    - **Job time** is separate — hours on a **client job** — do not emit employee_actions for those; return empty actions.

    If you cannot identify the employee with confidence, ask in `assistant_sms` instead of guessing.

    ## Time inference
    - "8am" → T08:00:00, "4pm" → T16:00:00, "noon" → T12:00:00, "3:30pm" → T15:30:00
    - Use today's date (#{today}) unless otherwise stated.

    ## Examples
    SMS "picked Henry up at 8am" → clock_in for Henry, clocked_in_at = today T08:00:00
    SMS "Henry took lunch from noon to 1pm" → lunch for Henry, 12:00–13:00
    SMS "dropped Henry off at home at 4pm" → clock_out for Henry, clocked_out_at = today T16:00:00
    SMS "Bob worked from 8am to 4pm today" → log_shift for Bob, in/out today 08:00–16:00
    SMS "Bob arrived 8am" (morning) → clock_in; later SMS "Bob left at 4pm" → clock_out (use open_entry)
    SMS "Angela's address is 123 Main" → no employee events → { "assistant_sms": null, "actions": [] }
    """
  end
end
