defmodule RompCrm.Ai.SmsJobExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double: returns predictable JSON-shaped maps without calling Anthropic.

  - `STUB_JSON ` + JSON — raw map passthrough (tests).
  - `STUB_UPDATE ` + JSON — production-shaped stubs:
    - `{"job_id": <int>, "updates": {...}}` — preferred (matches Claude after snapshot rollout).
    - `{"match": {...}, "updates": {...}}` — fallback heuristic matching tests.

  Second argument (`jobs_snapshot`) is ignored.
  """
  def extract(raw_message, _jobs_snapshot \\ []) when is_binary(raw_message) do
    trimmed = String.trim(raw_message)

    case trimmed do
      <<"STUB_JSON ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{} = map} ->
            {:ok, Map.put_new(map, "assistant_sms", "Stub: applied.")}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_UPDATE ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{"job_id" => job_id, "updates" => %{} = updates}} ->
            {:ok,
             %{
               "intent" => "update",
               "job_id" => job_id,
               "updates" => updates,
               "assistant_sms" => "Stub: updated job."
             }}

          {:ok, %{"match" => %{} = match, "updates" => %{} = updates}} ->
            {:ok,
             %{
               "intent" => "update",
               "match" => match,
               "updates" => updates,
               "assistant_sms" => "Stub: matched update."
             }}

          {:ok, _} ->
            {:error, :stub_missing_job_id_or_match_updates}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_CLARIFY ", rest::binary>> ->
        msg = String.trim(rest)

        {:ok,
         %{
           "assistant_sms" => if(msg != "", do: msg, else: "Which job did you mean?"),
           "actions" => []
         }}

      _ ->
        {:ok,
         %{
           "assistant_sms" => "Added lead from SMS.",
           "intent" => "create",
           "job" => %{
             "client_name" => "Test SMS Lead",
             "address" => nil,
             "phone" => nil,
             "work_description" => String.slice(trimmed, 0, 500),
             "priority" => "normal",
             "status" => "lead",
             "referred_by" => nil,
             "notes" => nil,
             "next_action" => nil
           }
         }}
    end
  end
end
