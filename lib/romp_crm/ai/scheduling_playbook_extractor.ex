defmodule RompCrm.Ai.SchedulingPlaybookExtractor do
  @moduledoc """
  Extracts scheduling prefs updates, playbook rules, and scheduling memories from
  contractor natural language (setup or ongoing preference updates).
  """

  def extract(raw) when is_binary(raw) do
    mod = Application.get_env(:romp_crm, :scheduling_playbook_adapter, __MODULE__.Anthropic)
    mod.extract(raw)
  end

  @doc "Parses structured setup reply (work hours + A/B/C outreach)."
  def extract_structured(body) when is_binary(body) do
    mod = Application.get_env(:romp_crm, :scheduling_playbook_adapter, __MODULE__.Anthropic)
    mod.extract_structured(body)
  end

  @doc "Detects ongoing scheduling preference updates from contractor SMS."
  def extract_playbook_update(body, context \\ %{}) when is_binary(body) do
    mod = Application.get_env(:romp_crm, :scheduling_playbook_adapter, __MODULE__.Anthropic)
    mod.extract_playbook_update(body, context)
  end
end
