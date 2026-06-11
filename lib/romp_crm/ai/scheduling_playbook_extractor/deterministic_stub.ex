defmodule RompCrm.Ai.SchedulingPlaybookExtractor.DeterministicStub do
  @moduledoc false

  def extract("STUB_PLAYBOOK " <> json) do
    case Jason.decode(json) do
      {:ok, map} -> {:ok, map}
      _ -> {:error, :invalid_json}
    end
  end

  def extract(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, %{"structured" => structured} = map} ->
        open = Map.get(map, "open_ended", "")
        {:ok, merge_open_ended(structured, open)}

      _ ->
        {:ok, %{"prefs_updates" => %{}, "playbook_rules" => [], "scheduling_memories" => [], "assistant_summary" => "Saved."}}
    end
  end

  def extract_structured(body) do
    {:ok,
     %{
       "structured" => %{
         "work_hours_summary" => String.trim(body),
         "outreach_style" => outreach_from_body(body),
         "outreach_style_label" => outreach_label(body)
       },
       "prefs_updates" => prefs_from_structured(body)
     }}
  end

  def extract_playbook_update("STUB_PLAYBOOK_UPDATE " <> json, _ctx) do
    case Jason.decode(json) do
      {:ok, map} -> {:ok, map}
      _ -> {:error, :invalid_json}
    end
  end

  def extract_playbook_update(body, _ctx) do
  t = String.downcase(body)

    rules =
      cond do
        String.contains?(t, "confirm") and String.contains?(t, "before") ->
          [
            %{
              "kind" => "confirm_before_offer_slots",
              "config" => %{"enabled" => true},
              "source_text" => body
            }
          ]

        true ->
          []
      end

    {:ok,
     %{
       "prefs_updates" => %{},
       "playbook_rules" => rules,
       "scheduling_memories" => [],
       "assistant_summary" => "Updated your scheduling preferences."
     }}
  end

  defp merge_open_ended(structured, open) when is_map(structured) do
    stored_prefs = Map.get(structured, "prefs_updates") || %{}

    base = %{
      "prefs_updates" =>
        Map.merge(prefs_from_structured(structured), stored_prefs),
      "playbook_rules" => [],
      "scheduling_memories" => [],
      "assistant_summary" => "Scheduling preferences saved."
    }

    if is_binary(open) and String.trim(open) != "" do
      rules = playbook_from_open(open)
      Map.put(base, "playbook_rules", rules)
    else
      base
    end
  end

  defp prefs_from_structured(body) when is_binary(body) do
    %{
      "customer_outreach_style" => outreach_from_body(body),
      "workday_start" => "08:00",
      "workday_end" => "17:00",
      "work_days" => [1, 2, 3, 4, 5]
    }
  end

  defp prefs_from_structured(map) when is_map(map) do
    %{
      "customer_outreach_style" =>
        Map.get(map, "outreach_style") || outreach_from_body(Map.get(map, "work_hours_summary", ""))
    }
  end

  defp outreach_from_body(body) do
    t = String.downcase(body)

    cond do
      Regex.match?(~r/\b(a\b|ask)/, t) -> "ask"
      Regex.match?(~r/\b(b\b|offer specific|offer times first)/, t) -> "offer"
      true -> "offer_then_ask"
    end
  end

  defp outreach_label(body) do
    case outreach_from_body(body) do
      "ask" -> "ask what works"
      "offer" -> "offer times first"
      _ -> "offer times and invite alternatives"
    end
  end

  defp playbook_from_open(open) do
    t = String.downcase(open)
    rules = []

    rules =
      if String.contains?(t, "greet") or String.contains?(t, "hey,") do
        [
          %{
            "kind" => "greeting_template",
            "config" => %{"template" => String.trim(open)},
            "source_text" => open
          }
          | rules
        ]
      else
        rules
      end

    rules =
      if String.contains?(t, "confirm") and String.contains?(t, "before") do
        [
          %{
            "kind" => "confirm_before_offer_slots",
            "config" => %{"enabled" => true},
            "source_text" => open
          }
          | rules
        ]
      else
        rules
      end

    rules =
      if String.contains?(t, "week out") or String.contains?(t, "at least a week") do
        [%{"kind" => "min_lead_days", "config" => %{"days" => 7}, "source_text" => open} | rules]
      else
        rules
      end

    rules =
      if String.contains?(t, "soonest") or String.contains?(t, "asap") do
        [
          %{
            "kind" => "scheduling_bias",
            "config" => %{"bias" => "asap"},
            "source_text" => open
          }
          | rules
        ]
      else
        rules
      end

    if rules == [] and String.trim(open) != "" do
      [%{"kind" => "custom_instruction", "config" => %{}, "source_text" => open}]
    else
      rules
    end
  end
end
