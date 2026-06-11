defmodule RompCrm.Scheduling.Playbook do
  @moduledoc """
  Per-technician scheduling playbook rules: greetings, outreach style overrides,
  confirm-before-offer workflow, and free-form instructions for AI prompts.
  """

  import Ecto.Query

  alias RompCrm.Bookings.Escalations
  alias RompCrm.Repo
  alias RompCrm.Scheduling.{PlaybookRule, Prefs}

  @doc false
  def needs_setup?(%{scheduling_setup_completed_at: nil}), do: true
  def needs_setup?(_), do: false

  @doc "Active rules for a technician, newest per kind wins when kind is singular."
  def list_rules(business_id, user_id) when is_integer(business_id) and is_integer(user_id) do
    Repo.all(
      from r in PlaybookRule,
        where:
          r.business_id == ^business_id and r.technician_user_id == ^user_id and r.active == true,
        order_by: [desc: r.priority, desc: r.id]
    )
  end

  def snapshot_for_ai(business_id, user_id) when is_integer(business_id) and is_integer(user_id) do
  rules = list_rules(business_id, user_id)

    %{
      "rules" =>
        Enum.map(rules, fn r ->
          %{
            "kind" => r.kind,
            "config" => r.config || %{},
            "source_text" => r.source_text
          }
        end),
      "greeting_template" => rule_config(rules, "greeting_template", "template"),
      "confirm_before_offer_slots" => confirm_before_offer_slots?(rules),
      "custom_instructions" =>
        rules
        |> Enum.filter(&(&1.kind == "custom_instruction"))
        |> Enum.map(& &1.source_text)
        |> Enum.reject(&is_nil/1),
      "summary" => compile_summary(rules)
    }
  end

  def confirm_before_offer_slots?(business_id, user_id) when is_integer(business_id) do
    confirm_before_offer_slots?(list_rules(business_id, user_id))
  end

  def confirm_before_offer_slots?(rules) when is_list(rules) do
    case rule_config(rules, "confirm_before_offer_slots", "enabled") do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  def greeting_template(business_id, user_id) do
    list_rules(business_id, user_id)
    |> rule_config("greeting_template", "template")
  end

  @doc "Upserts a singular rule kind (deactivates prior rows of the same kind)."
  def upsert_rule!(business_id, user_id, kind, config, source_text \\ nil)
      when is_integer(business_id) and is_integer(user_id) and is_binary(kind) do
    Repo.transaction(fn ->
      Repo.update_all(
        from(r in PlaybookRule,
          where:
            r.business_id == ^business_id and r.technician_user_id == ^user_id and
              r.kind == ^kind and r.active == true
        ),
        set: [active: false]
      )

      {:ok, rule} =
        %PlaybookRule{}
        |> PlaybookRule.changeset(%{
          business_id: business_id,
          technician_user_id: user_id,
          kind: kind,
          config: config || %{},
          source_text: source_text,
          active: true
        })
        |> Repo.insert()

      rule
    end)
    |> case do
      {:ok, rule} -> rule
      {:error, reason} -> raise "playbook upsert failed: #{inspect(reason)}"
    end
  end

  def add_custom_instruction!(business_id, user_id, text) when is_binary(text) do
    %PlaybookRule{}
    |> PlaybookRule.changeset(%{
      business_id: business_id,
      technician_user_id: user_id,
      kind: "custom_instruction",
      config: %{},
      source_text: String.trim(text),
      active: true
    })
    |> Repo.insert!()
  end

  @doc "Applies extractor output: prefs updates, playbook rules, scheduling memories."
  def apply_extraction!(business_id, user_id, user, extraction) when is_map(extraction) do
    prefs_updates = Map.get(extraction, "prefs_updates") || Map.get(extraction, :prefs_updates) || %{}

    if prefs_updates != %{} do
      json = Prefs.merge_encoded(user.scheduling_prefs_json, prefs_updates)
      {:ok, user} = RompCrm.Accounts.update_user_scheduling_prefs(user, json)
      user
    else
      user
    end
    |> then(fn u ->
      rules = Map.get(extraction, "playbook_rules") || Map.get(extraction, :playbook_rules) || []

      u =
        Enum.reduce(rules, u, fn rule, acc_user ->
          kind = rule["kind"] || rule[:kind]
          config = rule["config"] || rule[:config] || %{}
          source = rule["source_text"] || rule[:source_text]

          cond do
            kind == "custom_instruction" and is_binary(source) and String.trim(source) != "" ->
              add_custom_instruction!(business_id, user_id, source)
              acc_user

            kind == "min_lead_days" ->
              days = Map.get(config, "days") || Map.get(config, :days) || 0
              upsert_rule!(business_id, user_id, kind, config, source)
              json = Prefs.merge_encoded(acc_user.scheduling_prefs_json, %{"min_lead_days" => days})
              {:ok, refreshed} = RompCrm.Accounts.update_user_scheduling_prefs(acc_user, json)
              refreshed

            kind == "scheduling_bias" ->
              bias = Map.get(config, "bias") || Map.get(config, :bias)
              upsert_rule!(business_id, user_id, kind, config, source)

              if bias do
                json = Prefs.merge_encoded(acc_user.scheduling_prefs_json, %{"scheduling_bias" => bias})
                {:ok, refreshed} = RompCrm.Accounts.update_user_scheduling_prefs(acc_user, json)
                refreshed
              else
                acc_user
              end

            is_binary(kind) ->
              upsert_rule!(business_id, user_id, kind, config, source)
              acc_user

            true ->
              acc_user
          end
        end)

      memories =
        Map.get(extraction, "scheduling_memories") || Map.get(extraction, :scheduling_memories) || []

      Enum.each(memories, fn mem ->
        topic = mem["topic"] || mem[:topic]
        answer = mem["answer"] || mem[:answer] || mem["answer_text"] || mem[:answer_text]

        if is_binary(topic) and is_binary(answer) and String.trim(topic) != "" do
          Escalations.create_memory(%{
            business_id: business_id,
            topic: String.trim(topic),
            answer_text: String.trim(answer)
          })
        end
      end)

      u
    end)
  end

  def playbook_update_message?(body) when is_binary(body) do
    t = String.downcase(String.trim(body))

    Regex.match?(
      ~r/\b(from now on|always|never|scheduling pref|how you schedule|greeting|confirm before|book at least|week out|soonest|asap)\b/,
      t
    ) or String.starts_with?(t, "scheduling:")
  end

  def deactivate_rule!(id, business_id, user_id) do
    case Repo.one(
           from r in PlaybookRule,
             where:
               r.id == ^id and r.business_id == ^business_id and
                 r.technician_user_id == ^user_id
         ) do
      nil ->
        {:error, :not_found}

      rule ->
        rule
        |> PlaybookRule.changeset(%{active: false})
        |> Repo.update()
    end
  end

  defp rule_config(rules, kind, key) do
    rules
    |> Enum.find(&(&1.kind == kind))
    |> case do
      %{config: %{} = config} -> Map.get(config, key) || Map.get(config, String.to_atom(key))
      _ -> nil
    end
  end

  defp compile_summary(rules) do
    base =
      []
      |> maybe_add(
        rule_config(rules, "greeting_template", "template"),
        fn t -> "Greeting: #{t}" end
      )
      |> maybe_add(
        rule_config(rules, "confirm_before_offer_slots", "enabled"),
        fn _ -> "Confirm with contractor before offering specific times to customers" end
      )

    customs =
      rules
      |> Enum.filter(&(&1.kind == "custom_instruction"))
      |> Enum.map(& &1.source_text)
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    Enum.join(base ++ customs, ". ")
  end

  defp maybe_add(parts, nil, _), do: parts
  defp maybe_add(parts, false, _), do: parts
  defp maybe_add(parts, val, fun), do: parts ++ [fun.(val)]
end
