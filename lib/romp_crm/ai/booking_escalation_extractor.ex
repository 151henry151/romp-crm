defmodule RompCrm.Ai.BookingEscalationExtractor do
  @moduledoc """
  Classifies a contractor SMS when open booking escalations exist for their
  workspace: direct outreach, answer + memory follow-up, memory yes/no, or
  unrelated (fall through to the unified CRM extractor).
  """

  def extract(raw_message, escalations, prior_turns \\ [], opts \\ [])
      when is_binary(raw_message) and is_list(escalations) do
    mod = Application.get_env(:romp_crm, :booking_escalation_adapter, __MODULE__.Anthropic)

    case mod.extract(raw_message, escalations, prior_turns, opts) do
      {:ok, %{} = attrs} -> parse_payload(attrs)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_payload(map) do
    map = stringify_keys(map)

    reply =
      case Map.get(map, "reply_sms") do
        s when is_binary(s) -> s |> String.trim() |> String.slice(0, 480)
        _ -> ""
      end

    resolved_id = parse_optional_id(Map.get(map, "resolved_escalation_id"))

    intent =
      map["intent"]
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> case do
        "" -> :not_escalation
        "not_escalation" -> :not_escalation
        "contractor_handling" -> :contractor_handling
        "provide_answer" -> :provide_answer
        "memory_decision" -> :memory_decision
        "complete_with_answer" -> :complete_with_answer
        _ -> :not_escalation
      end

    contractor_answer =
      case Map.get(map, "contractor_answer") do
        s when is_binary(s) ->
          t = String.trim(s)
          if t == "", do: nil, else: t

        _ ->
          nil
      end

    memory_summary =
      case Map.get(map, "memory_summary") do
        s when is_binary(s) ->
          t = String.trim(s)
          if t == "", do: nil, else: t

        _ ->
          nil
      end

    save_memory =
      case Map.get(map, "save_memory") do
        true -> true
        false -> false
        "true" -> true
        "false" -> false
        _ -> nil
      end

    {:ok,
     %{
       reply_sms: reply,
       resolved_escalation_id: resolved_id,
       intent: intent,
       contractor_answer: contractor_answer,
       memory_summary: memory_summary,
       save_memory: save_memory
     }}
  end

  defp parse_optional_id(n) when is_integer(n) and n > 0, do: n

  defp parse_optional_id(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp parse_optional_id(_), do: nil

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
