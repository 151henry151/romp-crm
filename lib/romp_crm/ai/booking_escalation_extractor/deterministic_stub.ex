defmodule RompCrm.Ai.BookingEscalationExtractor.DeterministicStub do
  @moduledoc false

  def extract(raw_message, _escalations \\ [], _prior_turns \\ [], _opts \\ [])
      when is_binary(raw_message) do
    trimmed = String.trim(raw_message)

    if String.starts_with?(trimmed, "STUB_ESCALATION ") do
      case Jason.decode(String.trim(String.replace_prefix(trimmed, "STUB_ESCALATION ", ""))) do
        {:ok, %{} = map} ->
          {:ok,
           map
           |> Map.put_new("reply_sms", "")
           |> Map.put_new("resolved_escalation_id", nil)
           |> Map.put_new("intent", "not_escalation")}

        _ ->
          {:error, :stub_bad_json}
      end
    else
      {:ok,
       %{
         "reply_sms" => "",
         "resolved_escalation_id" => nil,
         "intent" => "not_escalation"
       }}
    end
  end
end
