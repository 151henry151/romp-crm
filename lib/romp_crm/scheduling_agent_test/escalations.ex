defmodule RompCrm.SchedulingAgentTest.Escalations do
  @moduledoc false

  alias RompCrm.Ai.BookingEscalationExtractor
  alias RompCrm.SchedulingAgentTest.{Notifications, Sandbox}

  @default_client_reply "I don't have the answer to that, but I've reached out to a live person on our team to find out for you. I'll get back to you as soon as I have a response."

  def list_open(state) do
    (state["pending_escalations"] || [])
    |> Enum.filter(fn e -> e["status"] in ["pending_contractor", "pending_memory_confirm"] end)
  end

  def escalate_from_client(state, link, question_text, result) do
    question = String.trim(to_string(question_text))
    client_name = client_name_for_link(state, link)
    phone = link["client_phone_normalized"] || ""

    reply =
      case result do
        %{reply_sms: s} when is_binary(s) and s != "" -> String.trim(s)
        _ -> @default_client_reply
      end

    id = state["next_escalation_id"] || 1

    escalation = %{
      "id" => id,
      "status" => "pending_contractor",
      "booking_link_id" => link["id"],
      "client_name" => client_name,
      "phone_normalized" => phone,
      "question_text" => question,
      "contractor_answer" => nil,
      "memory_candidate" => nil
    }

    contractor_msg = Notifications.client_question_message(client_name, phone, question)

    state =
      state
      |> Map.update!("pending_escalations", &((&1 || []) ++ [escalation]))
      |> Map.put("next_escalation_id", id + 1)
      |> Sandbox.append_contractor_assistant(contractor_msg)

    {state, reply}
  end

  @doc """
  When open sandbox escalations exist, try to interpret the contractor's reply.
  Returns `{:handled, state, contractor_reply, client_outreach}` or `:continue`.
  """
  def handle_contractor_reply(state, _user, _business_id, body) do
    escalations = list_open(state)

    if escalations == [] do
      :continue
    else
      prior = Sandbox.contractor_prior_turns(state) |> Enum.drop(-1)

      case BookingEscalationExtractor.extract(body, escalation_context(escalations), prior) do
        {:ok, %{intent: :not_escalation}} ->
          :continue

        {:ok, result} ->
          apply_contractor_result(state, result, escalations)

        {:error, _} ->
          :continue
      end
    end
  end

  defp apply_contractor_result(state, result, escalations) do
    escalation = resolve_escalation(result.resolved_escalation_id, escalations)

    escalation =
      escalation ||
        if length(escalations) == 1, do: List.first(escalations), else: nil

    case escalation do
      nil ->
        names = Enum.map_join(escalations, ", ", & &1["client_name"])
        reply = "Which client question are you replying about? #{names}"
        {:handled, Sandbox.append_contractor_assistant(state, reply), reply, nil}

      esc ->
        do_apply_intent(state, result, esc)
    end
  end

  defp do_apply_intent(state, %{intent: :contractor_handling} = result, escalation) do
    state = update_escalation(state, escalation, %{"status" => "contractor_handling"})

    reply =
      nonempty(result.reply_sms) ||
        "Got it — we'll leave #{escalation["client_name"]} to you."

    {:handled, Sandbox.append_contractor_assistant(state, reply), reply, nil}
  end

  defp do_apply_intent(state, %{intent: :provide_answer} = result, escalation) do
    answer = result.contractor_answer || ""

    if answer == "" do
      reply = "What should I tell #{escalation["client_name"]}?"
      {:handled, Sandbox.append_contractor_assistant(state, reply), reply, nil}
    else
      memory = result.memory_summary || default_memory_summary(escalation, answer)

      state =
        update_escalation(state, escalation, %{
          "status" => "pending_memory_confirm",
          "contractor_answer" => answer,
          "memory_candidate" => memory
        })

      reply =
        nonempty(result.reply_sms) ||
          "Ok — I'll let #{escalation["client_name"]} know. Should I also remember this for similar future questions? (#{memory}) Reply yes or no."

      {:handled, Sandbox.append_contractor_assistant(state, reply), reply, nil}
    end
  end

  defp do_apply_intent(state, %{intent: :memory_decision} = result, escalation) do
    if escalation["status"] != "pending_memory_confirm" do
      reply = "I don't have a pending answer to relay for #{escalation["client_name"]}."
      {:handled, Sandbox.append_contractor_assistant(state, reply), reply, nil}
    else
      finish_with_relay(state, escalation, result.save_memory == true, result.reply_sms)
    end
  end

  defp do_apply_intent(state, %{intent: :complete_with_answer} = result, escalation) do
    answer = result.contractor_answer || escalation["contractor_answer"] || ""

    state =
      update_escalation(state, escalation, %{
        "contractor_answer" => answer,
        "memory_candidate" => result.memory_summary || default_memory_summary(escalation, answer)
      })

    finish_with_relay(state, escalation, result.save_memory == true, result.reply_sms)
  end

  defp do_apply_intent(state, _result, escalation) do
    reply = "Still waiting on how to answer #{escalation["client_name"]}'s question."
    {:handled, Sandbox.append_contractor_assistant(state, reply), reply, nil}
  end

  defp finish_with_relay(state, escalation, _save_memory?, contractor_reply) do
    answer = escalation["contractor_answer"] || ""

    client_body =
      "Thanks for waiting — regarding your question about #{escalation["question_text"]}: #{answer}"

    state =
      state
      |> update_escalation(escalation, %{"status" => "resolved"})
      |> Sandbox.append_client_turn("scheduling_assistant", client_body)

    contractor_msg =
      nonempty(contractor_reply) ||
        "Done — I told #{escalation["client_name"]}. (Test workspace — customer reply shown in the right pane.)"

    {:handled, Sandbox.append_contractor_assistant(state, contractor_msg), contractor_msg, client_body}
  end

  defp escalation_context(escalations) do
    Enum.map(escalations, fn e ->
      %{
        "escalation_id" => e["id"],
        "status" => e["status"],
        "client_name" => e["client_name"],
        "client_phone" => e["phone_normalized"],
        "question_text" => e["question_text"],
        "contractor_answer" => e["contractor_answer"],
        "memory_candidate" => e["memory_candidate"]
      }
    end)
  end

  defp resolve_escalation(nil, [only]), do: only

  defp resolve_escalation(id, escalations) when is_integer(id) do
    Enum.find(escalations, &(&1["id"] == id))
  end

  defp resolve_escalation(id, escalations) when is_binary(id) do
    case Integer.parse(id) do
      {n, _} -> resolve_escalation(n, escalations)
      :error -> nil
    end
  end

  defp resolve_escalation(_, _), do: nil

  defp update_escalation(state, %{ "id" => id}, attrs) do
    escalations =
      Enum.map(state["pending_escalations"] || [], fn e ->
        if e["id"] == id, do: Map.merge(e, attrs), else: e
      end)

    Map.put(state, "pending_escalations", escalations)
  end

  defp client_name_for_link(state, link) do
    case Enum.find(state["clients"] || [], &(&1["id"] == link["client_id"])) do
      %{"client_name" => name} when is_binary(name) and name != "" -> name
      _ -> "A client"
    end
  end

  defp default_memory_summary(escalation, answer) do
    q = escalation["question_text"] || "customer question"
    "When customers ask: #{String.slice(q, 0, 120)} → #{String.slice(answer, 0, 200)}"
  end

  defp nonempty(s) when is_binary(s) do
    t = String.trim(s)
    if t == "", do: nil, else: t
  end

  defp nonempty(_), do: nil
end
