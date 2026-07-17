defmodule RompCrm.Ai.SmsRoleClassifier.DeterministicStub do
  @moduledoc false

  # Test double — mirrors prior dual-role heuristics so existing router tests stay stable.
  # Production uses Anthropic.

  def classify(body, context) when is_binary(body) and is_map(context) do
    trimmed = String.trim(body)

    cond do
      String.starts_with?(trimmed, "STUB_ROLE:") ->
        role = trimmed |> String.replace_prefix("STUB_ROLE:", "") |> String.trim() |> String.downcase()

        case role do
          "client" -> {:ok, :client}
          "contractor" -> {:ok, :contractor}
          _ -> {:ok, :ask}
        end

      Map.get(context, :pending_prompt, false) == true ->
        cond do
          Regex.match?(~r/\b(schedul|appointment|booking|customer|client|service\s+call)\b/i, trimmed) ->
            {:ok, :client}

          Enum.any?(List.wrap(Map.get(context, :business_names, [])), fn name ->
            is_binary(name) and name != "" and
              String.contains?(String.downcase(trimmed), String.downcase(name))
          end) ->
            {:ok, :client}

          Regex.match?(~r/\b(romp\s*crm|my\s+jobs?\b|my\s+clients?\b|contractor|account|workspace)\b/i, trimmed) ->
            {:ok, :contractor}

          true ->
            {:ok, :ask}
        end

      Map.get(context, :dual_role, false) == true ->
        if Regex.match?(
             ~r/\b(create\s+(a\s+)?(new\s+)?job|add\s+(a\s+)?(new\s+)?lead|delete\s+(all\s+)?(my\s+)?jobs?|clock\s+(in|out)|my\s+jobs?\b|my\s+clients?\b|remind\s+me\b|time\s+entr|employee\s+hours?|workspace\b|romp\s*crm\b)\b/i,
             trimmed
           ) do
          {:ok, :ask}
        else
          {:ok, :client}
        end

      true ->
        {:ok, :client}
    end
  end
end
