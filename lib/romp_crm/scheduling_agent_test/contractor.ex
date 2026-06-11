defmodule RompCrm.SchedulingAgentTest.Contractor do
  @moduledoc false

  require Logger

  alias RompCrm.Ai.SmsUnifiedInboundExtractor
  alias RompCrm.Bookings.ClientInvitationSms
  alias RompCrm.Bookings.OpeningsPreview
  alias RompCrm.Reminders
  alias RompCrm.SchedulingAgentTest.{ErrorReply, Escalations, Sandbox}
  alias RompCrm.SmsBookingConsent
  alias RompCrm.SmsPendingBookingProposals
  alias RompCrm.Twilio.Phone
  alias RompCrm.Twilio.SmsReplyBuilder

  @doc """
  Processes a contractor message in the sandbox. Returns
  `{:ok, state, %{contractor_reply: ..., client_outreach: nil | text}}`.
  """
  def process(state, user, business_id, body) when is_binary(body) do
    body = String.trim(body)
    state = Sandbox.append_contractor_turn(state, body)

    case Escalations.handle_contractor_reply(state, user, business_id, body) do
      {:handled, state, reply, client_sms} ->
        state =
          if client_sms do
            Sandbox.append_client_turn(state, "scheduling_assistant", client_sms)
          else
            state
          end

        {:ok, state, %{contractor_reply: reply, client_outreach: client_sms}}

      :continue ->
        continue_contractor(state, user, business_id, body)
    end
  end

  defp continue_contractor(state, user, business_id, body) do
    case maybe_apply_pending_booking(state, user, business_id, body) do
      {:applied, state, reply, client_sms} ->
        {:ok, state, %{contractor_reply: reply, client_outreach: client_sms}}

      :continue ->
        extract_and_apply(state, user, business_id, body)
    end
  end

  defp maybe_apply_pending_booking(state, user, business_id, body) do
    if SmsPendingBookingProposals.confirmation_message?(body) and state["pending_booking_proposal"] do
      proposal = state["pending_booking_proposal"]
      attrs = proposal_to_initiate(proposal, state)

      case Sandbox.create_booking_link(state, attrs) do
        {:ok, state, link, client} ->
          client_sms =
            ClientInvitationSms.compose(
              client["client_name"],
              link,
              business_id,
              user.id
            )

          reply =
            "Sent #{client["client_name"]} a test scheduling text for the #{link["job_type_label"]} (sandbox only — no real SMS)."

          state =
            state
            |> Sandbox.clear_pending_booking()
            |> Sandbox.append_contractor_assistant(reply)
            |> Sandbox.append_client_turn("scheduling_assistant", client_sms)

          {:applied, state, reply, client_sms}

        _ ->
          :continue
      end
    else
      :continue
    end
  end

  defp extract_and_apply(state, user, business_id, body) do
    prior = Sandbox.contractor_prior_turns(state) |> Enum.drop(-1)

    reminder_wall_tz =
      user.sms_reminder_prefs_json
      |> Reminders.decode_prefs_json()
      |> Map.get("timezone", "America/New_York")

    case SmsUnifiedInboundExtractor.extract(
           body,
           Sandbox.jobs_snapshot(state),
           [],
           [],
           prior,
           reminder_wall_tz: reminder_wall_tz,
           mms_image_blocks: [],
           recent_deleted_jobs: [],
           clients_snapshot: Sandbox.clients_snapshot(state),
           bookings_snapshot: Sandbox.bookings_snapshot(state)
         ) do
      {:ok, extracted} ->
        apply_extracted(state, user, business_id, body, extracted)

      {:error, reason} ->
        reply = ErrorReply.for_reason(reason)

        state =
          state
          |> Sandbox.append_contractor_assistant(reply)

        {:ok, state, %{contractor_reply: reply, client_outreach: nil}}
    end
  end

  defp apply_extracted(state, user, business_id, body, extracted) do
    assistant = extracted.assistant_sms
    job_ops = Enum.filter(extracted.job_operations, &match?({:create, _}, &1))
    booking_ops = extracted.booking_operations || []

    {job_ops, booking_ops, pending_proposals} =
      SmsBookingConsent.guard_operations(
        job_ops,
        booking_ops,
        body,
        extracted.proposed_booking_initiates || []
      )

    {state, created_jobs, job_results} = apply_job_creates(state, job_ops)

    {state, booking_results, client_sms} =
      apply_booking_ops(state, booking_ops, created_jobs, user, business_id)

    all_results = job_results ++ booking_results

    state =
      Enum.reduce(pending_proposals, state, fn proposal, acc ->
        job = match_created_job(created_jobs, proposal)

        attrs =
          proposal
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> then(fn m -> if job, do: Map.put(m, "job_id", job["id"]), else: m end)

        Sandbox.store_pending_booking(acc, attrs)
      end)

    combined_assistant = assistant

    reply =
      all_results
      |> then(&SmsReplyBuilder.compose(combined_assistant, &1))
      |> maybe_append_booking_ask(pending_proposals, business_id, user.id)

    state = Sandbox.append_contractor_assistant(state, reply)

    state =
      if client_sms do
        Sandbox.append_client_turn(state, "scheduling_assistant", client_sms)
      else
        state
      end

    {:ok, state, %{contractor_reply: reply, client_outreach: client_sms}}
  end

  defp apply_job_creates(state, ops) do
    {state, jobs} =
      Enum.reduce(ops, {state, []}, fn {:create, attrs}, {acc, jobs} ->
        attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

        case Sandbox.create_job(acc, attrs) do
          {:ok, acc, job} -> {acc, jobs ++ [job]}
          _ -> {acc, jobs}
        end
      end)

    results = Enum.map(jobs, fn job -> {:created, struct_job(job)} end)
    {state, jobs, results}
  end

  defp struct_job(job) do
    %RompCrm.Jobs.Job{
      id: job["id"],
      client_name: job["client_name"],
      phone: job["phone"],
      work_description: job["work_description"],
      status: String.to_existing_atom(job["status"] || "lead")
    }
  rescue
    ArgumentError ->
      %RompCrm.Jobs.Job{
        id: job["id"],
        client_name: job["client_name"],
        phone: job["phone"],
        work_description: job["work_description"],
        status: :lead
      }
  end

  defp apply_booking_ops(state, [], _created, _user, _bid),
    do: {state, [], nil}

  defp apply_booking_ops(state, ops, created_jobs, user, business_id) do
    Enum.reduce(ops, {state, [], nil}, fn op, {acc, results, client_sms} ->
      case op do
        {:booking_initiate, attrs} when is_map(attrs) ->
          matched = match_created_job_by_attrs(created_jobs, attrs)
          job_id = Map.get(attrs, :job_id) || (matched && matched["id"])

          initiate_attrs =
            attrs
            |> Map.new(fn {k, v} -> {to_string(k), v} end)
            |> Map.put("job_id", job_id)

          case Sandbox.create_booking_link(acc, initiate_attrs) do
            {:ok, acc, link, client} ->
              sms =
                ClientInvitationSms.compose(
                  client["client_name"],
                  link,
                  business_id,
                  user.id
                )

              summary =
                "Sent #{client["client_name"]} a test scheduling text for the #{link["job_type_label"]} (sandbox only)."

              {acc, results ++ [{:booking_done, summary}], sms}

            _ ->
              {acc, results ++ [{:skipped, :initiate_failed}], client_sms}
          end

        _ ->
          {acc, results ++ [{:skipped, :unsupported_in_test}], client_sms}
      end
    end)
  end

  defp match_created_job(jobs, proposal) when is_list(jobs) and is_map(proposal) do
    phone_norm = Phone.normalize_us(proposal["phone"] || proposal[:phone] || "")

    Enum.find(jobs, fn job ->
      job_phone = Phone.normalize_us(job["phone"] || "")

      cond do
        phone_norm != "" and job_phone != "" -> phone_norm == job_phone
        true -> same_name?(job["client_name"], proposal["client_name"] || proposal[:client_name])
      end
    end)
  end

  defp match_created_job_by_attrs(jobs, attrs) when is_map(attrs) do
    phone = Map.get(attrs, :phone) || Map.get(attrs, "phone") || ""
    name = Map.get(attrs, :client_name) || Map.get(attrs, "client_name")
    phone_norm = Phone.normalize_us(phone)

    Enum.find(jobs, fn job ->
      job_phone = Phone.normalize_us(job["phone"] || "")

      cond do
        phone_norm != "" and job_phone != "" -> phone_norm == job_phone
        true -> same_name?(job["client_name"], name)
      end
    end)
  end

  defp proposal_to_initiate(proposal, state) do
    job_id =
      case proposal["job_id"] do
        n when is_integer(n) -> n
        s when is_binary(s) ->
          case Integer.parse(s) do
            {n, _} -> n
            :error -> nil
          end

        _ ->
          nil
      end

    job_id =
      job_id ||
        case match_created_job(state["jobs"] || [], proposal) do
          %{"id" => id} -> id
          _ -> nil
        end

    %{
      "client_name" => proposal["client_name"] || "",
      "phone" => proposal["phone"] || "",
      "job_id" => job_id,
      "job_type_label" => proposal["job_type_label"] || "service call",
      "duration_min_minutes" => parse_int(proposal["duration_min_minutes"], 90),
      "duration_max_minutes" => parse_int(proposal["duration_max_minutes"], 120)
    }
  end

  defp maybe_append_booking_ask(reply, [], _business_id, _user_id), do: reply

  defp maybe_append_booking_ask(reply, [proposal | _], business_id, user_id) do
    openings =
      OpeningsPreview.phrase(
        business_id,
        user_id,
        Map.get(proposal, "duration_max_minutes") ||
          Map.get(proposal, :duration_max_minutes) || 120
      )

    name =
      (proposal["client_name"] || proposal[:client_name] || "the customer")
      |> to_string()
      |> String.split(" ")
      |> List.first()

    work = proposal["job_type_label"] || proposal[:job_type_label] || "the job"
    base = reply || "Lead saved in test workspace."

    cond do
      String.match?(base, ~r/\?/i) and openings != "" and not String.contains?(base, "openings") ->
        String.trim_trailing(base, ".") <> "." <> openings <> " Reply YES to text them."

      String.match?(base, ~r/\?/i) ->
        if String.match?(base, ~r/\b(yes|reply)\b/i), do: base, else: base <> " Reply YES to text them."

      true ->
        "#{base} Should I text #{name} to schedule the #{work}?#{openings} Reply YES to send the scheduling text."
    end
  end

  defp same_name?(a, b) when is_binary(a) and is_binary(b) do
    norm = fn s -> s |> String.downcase() |> String.trim() end
    norm.(a) != "" and norm.(a) == norm.(b)
  end

  defp same_name?(_, _), do: false

  defp parse_int(v, default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
