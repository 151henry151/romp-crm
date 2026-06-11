defmodule RompCrm.Bookings.EscalationCoordinator do
  @moduledoc """
  Client question escalations to the contractor and relaying answers back,
  with optional per-business scheduling memories.
  """

  require Logger

  alias RompCrm.Accounts.User
  alias RompCrm.Ai.BookingEscalationExtractor
  alias RompCrm.Bookings.{BookingLink, Escalation, Escalations}
  alias RompCrm.ContactInfo
  alias RompCrm.Repo
  alias RompCrm.SmsConversations
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @client_escalation_reply "I don't have the answer to that, but I've reached out to a live person on our team to find out for you. I'll get back to you as soon as I have a response."

  @doc """
  Creates an escalation from a client booking conversation and notifies the
  contractor. Returns `{:ok, escalation, client_reply_text}`.
  """
  def escalate_from_client(%BookingLink{} = link, attrs) when is_map(attrs) do
    link = Repo.preload(link, [:client, :technician_user])
    question = Map.get(attrs, :question_text) |> to_string() |> String.trim()
    client_name = client_display_name(link)

    with {:ok, %Escalation{} = escalation} <-
           Escalations.create_escalation(%{
             business_id: link.business_id,
             technician_user_id: link.technician_user_id,
             booking_link_id: link.id,
             client_id: link.client_id,
             client_phone_normalized: link.client_phone_normalized,
             client_name: client_name,
             question_text: question,
             status: "pending_contractor"
           }),
         :ok <- notify_contractor_of_question(escalation, link) do
      {:ok, escalation, client_reply(attrs)}
    end
  end

  @doc """
  When open escalations exist, try to handle the contractor's SMS. Returns
  `{:handled, reply}` or `:continue` for normal CRM processing.
  """
  def handle_contractor_message(%User{} = user, business_id, body_text)
      when is_integer(business_id) and is_binary(body_text) do
    escalations = Escalations.list_open_for_business(business_id)

    if escalations == [] do
      :continue
    else
      prior_turns = contractor_prior_turns(business_id, user)

      case BookingEscalationExtractor.extract(body_text, escalation_context(escalations), prior_turns) do
        {:ok, %{intent: :not_escalation}} ->
          :continue

        {:ok, result} ->
          case apply_contractor_result(result, escalations, business_id) do
            {:ok, reply} -> {:handled, reply}
            :continue -> :continue
          end

        {:error, reason} ->
          Logger.warning("Booking escalation extraction failed: #{inspect(reason)}")
          :continue
      end
    end
  end

  defp apply_contractor_result(%{intent: :not_escalation}, _, _), do: :continue

  defp apply_contractor_result(result, escalations, business_id) do
    case resolve_escalation(result.resolved_escalation_id, escalations) do
      nil ->
        if length(escalations) == 1 do
          apply_contractor_result(%{result | resolved_escalation_id: List.first(escalations).id}, escalations, business_id)
        else
          {:ok, "Which client question are you replying about? " <> Enum.map_join(escalations, ", ", & &1.client_name)}
        end

      %Escalation{} = escalation ->
        do_apply_contractor_intent(result, escalation, business_id)
    end
  end

  defp do_apply_contractor_intent(%{intent: :contractor_handling} = result, escalation, _business_id) do
    with {:ok, _} <- Escalations.mark_contractor_handling(escalation) do
      reply =
        nonempty(result.reply_sms) ||
          "Got it — we'll leave #{escalation.client_name} to you."

      {:ok, reply}
    end
  end

  defp do_apply_contractor_intent(%{intent: :provide_answer} = result, escalation, _business_id) do
    answer = result.contractor_answer || ""

    if answer == "" do
      {:ok, "What should I tell #{escalation.client_name}?"}
    else
      memory_candidate = result.memory_summary || default_memory_summary(escalation, answer)

      with {:ok, updated} <-
             Escalations.update_escalation(escalation, %{
               status: "pending_memory_confirm",
               contractor_answer: answer,
               memory_candidate: memory_candidate
             }) do
        reply =
          nonempty(result.reply_sms) ||
            "Ok — I'll let #{updated.client_name} know. Should I also remember this for similar future questions? (#{memory_candidate}) Reply yes or no."

        {:ok, reply}
      end
    end
  end

  defp do_apply_contractor_intent(%{intent: :memory_decision} = result, escalation, business_id) do
    if escalation.status != "pending_memory_confirm" do
      {:ok, "I don't have a pending answer to relay for #{escalation.client_name}."}
    else
      save? = result.save_memory == true
      finish_escalation(escalation, business_id, save?, result.reply_sms)
    end
  end

  defp do_apply_contractor_intent(%{intent: :complete_with_answer} = result, escalation, business_id) do
    answer = result.contractor_answer || escalation.contractor_answer || ""

    with {:ok, updated} <-
           Escalations.update_escalation(escalation, %{
             contractor_answer: answer,
             memory_candidate: result.memory_summary || default_memory_summary(escalation, answer)
           }) do
      save? = result.save_memory == true
      finish_escalation(updated, business_id, save?, result.reply_sms)
    end
  end

  defp do_apply_contractor_intent(_, escalation, _business_id) do
    {:ok, "Still waiting on how to answer #{escalation.client_name}'s question."}
  end

  defp finish_escalation(%Escalation{} = escalation, business_id, save_memory?, contractor_reply) do
    with :ok <- maybe_save_memory(escalation, business_id, save_memory?) |> memory_result(),
         {:ok, _client_reply} <- relay_answer_to_client(escalation),
         {:ok, _} <-
           Escalations.mark_resolved(escalation, %{
             memory_saved: save_memory?,
             client_relayed_at: DateTime.utc_now(:second)
           }) do
      contractor_msg =
        nonempty(contractor_reply) ||
          if save_memory? do
            "Done — I told #{escalation.client_name} and saved that for next time."
          else
            "Done — I told #{escalation.client_name}."
          end

      {:ok, contractor_msg}
    else
      {:error, _} = err -> err
      other -> other
    end
  end

  defp memory_result(:ok), do: :ok
  defp memory_result({:error, _} = err), do: err

  defp maybe_save_memory(_escalation, _business_id, false), do: :ok

  defp maybe_save_memory(%Escalation{} = escalation, business_id, true) do
    topic = escalation.memory_candidate || default_memory_summary(escalation, escalation.contractor_answer)

    case Escalations.create_memory(%{
           business_id: business_id,
           topic: topic,
           answer_text: escalation.contractor_answer,
           source_escalation_id: escalation.id
         }) do
      {:ok, _} -> :ok
      {:error, cs} -> {:error, cs}
    end
  end

  defp relay_answer_to_client(%Escalation{} = escalation) do
    answer = escalation.contractor_answer || ""

    body =
      "Thanks for waiting — regarding your question#{question_fragment(escalation)}: #{answer}"

    phone_norm = escalation.client_phone_normalized

    with e164 when is_binary(e164) <- Phone.to_e164(phone_norm),
         {:ok, _} <- Messages.send_sms(e164, body) do
      _ =
        SmsConversations.record_client_message(
          escalation.business_id,
          escalation.technician_user_id,
          phone_norm,
          "outbound",
          body
        )

      {:ok, body}
    else
      _ -> {:ok, body}
    end
  end

  defp notify_contractor_of_question(%Escalation{} = escalation, %BookingLink{} = link) do
    link = Repo.preload(link, :technician_user)
    tech = link.technician_user || Repo.get(User, escalation.technician_user_id)
    phone_display = ContactInfo.format_display(escalation.client_phone_normalized)

    body =
      "#{escalation.client_name} just asked me: \"#{escalation.question_text}\" " <>
        "Do you want me to relay an answer to them, or would you prefer to reach out to them directly? " <>
        "Their number is #{phone_display}."

    with %User{} <- tech,
         e164 when is_binary(e164) <- Phone.to_e164(tech.phone_normalized || tech.phone) do
      _ = Messages.send_sms(e164, body)
      :ok
    else
      _ -> :ok
    end
  end

  defp escalation_context(escalations) when is_list(escalations) do
    Enum.map(escalations, fn e ->
      %{
        "escalation_id" => e.id,
        "status" => e.status,
        "client_name" => e.client_name,
        "client_phone" => e.client_phone_normalized,
        "question_text" => e.question_text,
        "contractor_answer" => e.contractor_answer,
        "memory_candidate" => e.memory_candidate
      }
    end)
  end

  defp resolve_escalation(nil, [only]), do: only

  defp resolve_escalation(id, escalations) when is_integer(id) do
    Enum.find(escalations, &(&1.id == id))
  end

  defp resolve_escalation(_, _), do: nil

  defp contractor_prior_turns(business_id, %User{} = user) do
    phone_norm = user.phone_normalized || Phone.normalize_us(user.phone || "")

    if phone_norm != "" do
      SmsConversations.list_prior_turns_for_ai(business_id, phone_norm)
    else
      []
    end
  end

  defp client_display_name(%BookingLink{} = link) do
    cond do
      link.client && link.client.client_name not in [nil, ""] -> link.client.client_name
      true -> "A client"
    end
  end

  defp client_reply(attrs) do
    Map.get(attrs, :client_reply) |> present() || @client_escalation_reply
  end

  defp default_memory_summary(%Escalation{} = escalation, answer) do
    q = escalation.question_text |> String.slice(0, 120)
    a = answer |> String.slice(0, 120)
    "Q: #{q} → A: #{a}"
  end

  defp question_fragment(%Escalation{question_text: q}) when is_binary(q) and q != "" do
    short = if String.length(q) > 60, do: String.slice(q, 0, 57) <> "…", else: q
    " (#{short})"
  end

  defp question_fragment(_), do: ""

  defp nonempty(reply) when is_binary(reply) do
    case String.trim(reply) do
      "" -> nil
      t -> t
    end
  end

  defp nonempty(_), do: nil

  defp present(nil), do: nil

  defp present(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end
end
