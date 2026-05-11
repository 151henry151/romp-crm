defmodule RompCrm.Ai.SmsTimeExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double for `SmsTimeExtractor`.

  - `STUB_TIME_IN <JSON>` — `{"job_id": <int>, "started_at": "<iso>"}` → clock_in action.
  - `STUB_TIME_OUT <JSON>` — `{"job_id": <int>, "ended_at": "<iso>"}` → clock_out action.
  - Any other message → `{"actions": [], "assistant_sms": null}` (not a time-tracking message).
  """
  def extract(raw_message, _jobs_snapshot \\ [], _open_entries_snapshot \\ [])
      when is_binary(raw_message) do
    trimmed = String.trim(raw_message)

    case trimmed do
      <<"STUB_TIME_IN ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{"job_id" => job_id, "started_at" => started_at}} ->
            {:ok,
             %{
               "assistant_sms" => "Stub: clocked in.",
               "actions" => [
                 %{"intent" => "clock_in", "job_id" => job_id, "started_at" => started_at}
               ]
             }}

          {:ok, _} ->
            {:error, :stub_missing_fields}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_TIME_OUT ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{"job_id" => job_id, "ended_at" => ended_at}} ->
            {:ok,
             %{
               "assistant_sms" => "Stub: clocked out.",
               "actions" => [
                 %{"intent" => "clock_out", "job_id" => job_id, "ended_at" => ended_at}
               ]
             }}

          {:ok, _} ->
            {:error, :stub_missing_fields}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_JSON ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, payload} -> {:ok, payload}
          {:error, _} -> {:error, :stub_bad_json}
        end

      _ ->
        {:ok, %{"assistant_sms" => nil, "actions" => []}}
    end
  end
end
