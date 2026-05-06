defmodule JgsCrm.Ai.SmsJobExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double: returns predictable JSON-shaped maps without calling Anthropic.

  Prefix the SMS body with `STUB_UPDATE ` followed by JSON:
  `{"match":{...},"updates":{...}}` to exercise the update path.
  """
  def extract(raw_message) when is_binary(raw_message) do
    trimmed = String.trim(raw_message)

    case trimmed do
      <<"STUB_UPDATE ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{"match" => %{} = match, "updates" => %{} = updates}} ->
            {:ok, %{"intent" => "update", "match" => match, "updates" => updates}}

          {:ok, _} ->
            {:error, :stub_missing_match_updates}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      _ ->
        {:ok,
         %{
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
