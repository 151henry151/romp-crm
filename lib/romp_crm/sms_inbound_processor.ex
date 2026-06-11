defmodule RompCrm.SmsInboundProcessor do
  @moduledoc false

  require Logger

  alias RompCrm.Accounts.User
  alias RompCrm.Ai.SmsUnifiedInboundExtractor
  alias RompCrm.Bookings
  alias RompCrm.Bookings.Escalations
  alias RompCrm.BusinessAuditLogs
  alias RompCrm.BusinessAuditLogs.Detail
  alias RompCrm.Clients
  alias RompCrm.EmployeePermissions
  alias RompCrm.Employees
  alias RompCrm.Employees.TimeEntryActions
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Reminders
  alias RompCrm.Reminders.Reminder
  alias RompCrm.SmsConversations
  alias RompCrm.SmsMms
  alias RompCrm.SmsBookingInitiateInference
  alias RompCrm.SmsPendingJobProposals
  alias RompCrm.TimeTracking
  alias RompCrm.Twilio.MmsImageDownload
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone
  alias RompCrm.Twilio.SmsReplyBuilder

  @type delivery :: :twilio_sms | :in_app

  @doc """
  Process an inbound agent message (SMS webhook or in-app chat).
  Returns `{:ok, reply_text}` or `{:error, reason}`.
  """
  def process(%User{} = user, business_id, body_text, opts) when is_integer(business_id) do
    delivery = Keyword.get(opts, :delivery, :in_app)
    channel = Keyword.get(opts, :channel, channel_for_delivery(delivery))
    params = Keyword.get(opts, :params, %{"Body" => body_text})
    from_e164 = Keyword.get(opts, :from_e164, user.phone || "")
    message_sid = Keyword.get(opts, :message_sid, "in-app-#{System.unique_integer([:positive])}")

    ctx = %{
      delivery: delivery,
      channel: channel,
      params: params,
      from_e164: from_e164,
      message_sid: message_sid
    }

    deliver_inbound(user, business_id, body_text, ctx)
  end

  @doc false
  def deliver_from_twilio(params, user, business_id) when is_map(params) and is_integer(business_id) do
    body_text = (params["Body"] || "") |> to_string()
    from = (params["From"] || "") |> to_string()

    process(user, business_id, body_text,
      delivery: :twilio_sms,
      channel: "sms",
      params: params,
      from_e164: from,
      message_sid: (params["MessageSid"] || "") |> to_string()
    )
  end

  defp channel_for_delivery(:twilio_sms), do: "sms"
  defp channel_for_delivery(:in_app), do: "in_app"

  defp resolve_phone_norm(from, user) do
    norm = Phone.normalize_us(from)

    if norm != "" do
      norm
    else
      user.phone_normalized || ""
    end
  end

  defp inbound_sms_body_for_extraction(body_text, params)
       when is_binary(body_text) and is_map(params) do
    trimmed = String.trim(body_text)

    base =
      if trimmed == "" do
        "(Inbound SMS body empty.)"
      else
        trimmed
      end

    case twilio_media_url_suffix_for_prompt(params) do
      "" -> base
      suffix -> base <> suffix
    end
  end

  defp twilio_media_url_suffix_for_prompt(params) when is_map(params) do
    case parse_twilio_num_media(params) do
      n when n > 0 ->
        urls =
          for i <- 0..(n - 1) do
            k = "MediaUrl#{i}"

            case params[k] do
              u when is_binary(u) ->
                t = String.trim(u)
                if t != "", do: t, else: nil

              _ ->
                nil
            end
          end
          |> Enum.reject(&is_nil/1)

        if urls == [] do
          ""
        else
          lines =
            urls
            |> Enum.with_index(1)
            |> Enum.map_join("", fn {u, ix} -> "\n#{ix}. #{u}" end)

          "\n\n[Twilio MMS with #{length(urls)} attachment URL(s) — use each exact URL in attach_photo actions:]#{lines}\nEach job_actions entry: {\"intent\":\"attach_photo\",\"job_id\":<id from jobs snapshot>,\"media_url\":\"<url>\",\"work_item_title\":\"<optional substring of a work item title>\"}"
        end

      _ ->
        ""
    end
  end

  defp parse_twilio_num_media(params) do
    raw = params["NumMedia"] || ""

    case Integer.parse(to_string(raw)) do
      {n, _} -> min(max(n, 0), 10)
      :error -> 0
    end
  end

  defp deliver_inbound(user, business_id, body_text, ctx) do
    body_stored = SmsMms.body_for_storage(body_text, ctx.params)
    body_for_ai = inbound_sms_body_for_extraction(body_text, ctx.params)
    from = to_string(ctx.from_e164 || "")
    _to_num = to_string(ctx.params["To"] || "")
    message_sid = to_string(ctx.message_sid || "")
    phone_norm = resolve_phone_norm(from, user)

    Logger.info(
      "Agent inbound (#{ctx.channel}): sid=#{message_sid} user_id=#{user.id} business_id=#{business_id} body=#{inspect(body_text)}"
    )

    jobs_snapshot = Jobs.snapshot_for_sms_ai(business_id)
    clients_snapshot = Clients.snapshot_for_sms_ai(business_id)
    allowed_job_ids = MapSet.new(Enum.map(jobs_snapshot, fn row -> row["id"] end))

    open_time_entries = TimeTracking.snapshot_for_sms_ai(business_id)
    employees_snapshot = Employees.snapshot_for_sms_ai(business_id)
    allowed_employee_ids = MapSet.new(Enum.map(employees_snapshot, fn row -> row["id"] end))

    prior_turns =
      if phone_norm != "" do
        SmsConversations.list_prior_turns_for_ai(business_id, phone_norm)
      else
        []
      end

    reminder_wall_tz =
      user.sms_reminder_prefs_json
      |> Reminders.decode_prefs_json()
      |> Map.get("timezone", "America/New_York")

    recent_deleted_jobs = BusinessAuditLogs.recent_deleted_jobs_snapshot(business_id)

    escalation_result =
      if Escalations.open_for_business?(business_id) do
        RompCrm.Bookings.EscalationCoordinator.handle_contractor_message(
          user,
          business_id,
          body_text
        )
      else
        :continue
      end

    case escalation_result do
      {:handled, reply} ->
        sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply, %{
          message_sid: message_sid,
          outcome: "booking_escalation_handled",
          results: []
        })

      :continue ->
        :continue_escalation
    end
    |> case do
      {:ok, _} = done ->
        done

      :continue_escalation ->
        if phone_norm != "" and SmsPendingJobProposals.confirmation_message?(body_text) do
          handle_pending_proposals(
            ctx,
            from,
            user,
            business_id,
            phone_norm,
            body_text,
            body_stored,
            message_sid,
            body_for_ai,
            jobs_snapshot,
            allowed_job_ids,
            open_time_entries,
            employees_snapshot,
            allowed_employee_ids,
            prior_turns,
            reminder_wall_tz,
            recent_deleted_jobs,
            clients_snapshot
          )
        else
          :continue_extract
        end
    end
    |> case do
      {:ok, _} = done ->
        done

      :continue_extract ->
        handle_pending_proposals(
          ctx,
          from,
          user,
          business_id,
          phone_norm,
          body_text,
          body_stored,
          message_sid,
          body_for_ai,
          jobs_snapshot,
          allowed_job_ids,
          open_time_entries,
          employees_snapshot,
          allowed_employee_ids,
          prior_turns,
          reminder_wall_tz,
          recent_deleted_jobs,
          clients_snapshot
        )
    end
  end

  defp handle_pending_proposals(
         ctx,
         from,
         user,
         business_id,
         phone_norm,
         body_text,
         body_stored,
         message_sid,
         body_for_ai,
         jobs_snapshot,
         allowed_job_ids,
         open_time_entries,
         employees_snapshot,
         allowed_employee_ids,
         prior_turns,
         reminder_wall_tz,
         recent_deleted_jobs,
         clients_snapshot
       ) do
    if phone_norm != "" and SmsPendingJobProposals.confirmation_message?(body_text) do
      case SmsPendingJobProposals.apply_pending(business_id, user.id, phone_norm) do
        {:ok, results} ->
          reply =
            SmsReplyBuilder.compose(nil, results)
            |> case do
              "" -> "Confirmed—created the proposed job(s) in Romp CRM."
              r -> r
            end

          sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply, %{
            message_sid: message_sid,
            outcome: "pending_proposals_confirmed",
            results: results
          })

        :none ->
          :continue_extract

        {:error, :wrong_user} ->
          reply = "Couldn't apply pending jobs for this account."

          sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply, %{
            message_sid: message_sid,
            outcome: "pending_proposals_wrong_user",
            results: []
          })
      end
    else
      :continue_extract
    end
    |> case do
      {:ok, _} = done ->
        done

      :continue_extract ->
        mms_urls = SmsMms.media_urls_from_params(ctx.params)

        mms_image_blocks =
          mms_urls
          |> MmsImageDownload.fetch_for_vision()
          |> tap(fn blocks ->
            if mms_urls != [] and blocks == [] do
              Logger.warning(
                "Twilio SMS MMS vision: sid=#{message_sid} could not download #{length(mms_urls)} image(s) for analysis"
              )
            end
          end)

        extract_and_deliver_sms_ops(
          ctx,
          user,
          business_id,
          from,
          phone_norm,
          body_text,
          body_stored,
          body_for_ai,
          message_sid,
          jobs_snapshot,
          allowed_job_ids,
          open_time_entries,
          employees_snapshot,
          allowed_employee_ids,
          prior_turns,
          reminder_wall_tz,
          mms_urls,
          mms_image_blocks,
          recent_deleted_jobs,
          clients_snapshot
        )
    end
  end

  defp extract_and_deliver_sms_ops(
         ctx,
         user,
         business_id,
         from,
         phone_norm,
         body_text,
         body_stored,
         body_for_ai,
         message_sid,
         jobs_snapshot,
         allowed_job_ids,
         open_time_entries,
         employees_snapshot,
         allowed_employee_ids,
         prior_turns,
         reminder_wall_tz,
         mms_urls,
         mms_image_blocks,
         recent_deleted_jobs,
         clients_snapshot
       ) do
    case SmsUnifiedInboundExtractor.extract(
           body_for_ai,
           jobs_snapshot,
           open_time_entries,
           employees_snapshot,
           prior_turns,
           reminder_wall_tz: reminder_wall_tz,
           mms_image_blocks: mms_image_blocks,
           recent_deleted_jobs: recent_deleted_jobs,
           clients_snapshot: clients_snapshot,
           bookings_snapshot: Bookings.snapshot_for_sms_ai(business_id)
         ) do
      {:ok,
       %{
         assistant_sms: assistant,
         job_operations: job_ops_raw,
         time_operations: time_ops_raw,
         emp_operations: emp_ops_raw,
         reminder_operations: rem_ops_raw,
         booking_operations: booking_ops_raw,
         proposed_job_creates: proposed_raw,
         image_kind: image_kind
       }} ->
        proposed = fill_proposal_media_urls(proposed_raw, mms_urls)

        if proposed != [] do
          SmsPendingJobProposals.store!(
            business_id,
            user.id,
            phone_norm,
            image_kind,
            proposed
          )

          Logger.info(
            "Twilio SMS proposed job creates: sid=#{message_sid} business_id=#{business_id} count=#{length(proposed)} image_kind=#{inspect(image_kind)}"
          )

          reply =
            first_nonempty([assistant]) ||
              default_proposal_reply(proposed)

          sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply, %{
            message_sid: message_sid,
            outcome: "proposed_job_creates",
            proposed_count: length(proposed),
            image_kind: image_kind,
            results: []
          })
        else
          deliver_extracted_sms_ops(
            ctx,
            user,
            business_id,
            from,
            phone_norm,
            body_text,
            body_stored,
            message_sid,
            jobs_snapshot,
            allowed_job_ids,
            allowed_employee_ids,
            assistant,
            job_ops_raw,
            time_ops_raw,
            emp_ops_raw,
            rem_ops_raw,
            booking_ops_raw,
            ctx.params
          )
        end

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS unified extraction failed: sid=#{message_sid} from=#{from} reason=#{inspect(reason)}"
        )

        reply = sms_extraction_failed_reply(reason)

        sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply, %{
          message_sid: message_sid,
          outcome: "extraction_error",
          planned_job_ops: [],
          planned_time_ops: [],
          planned_emp_ops: [],
          planned_reminder_ops: [],
          extraction_error: inspect(reason),
          results: []
        })
    end
  end

  defp deliver_extracted_sms_ops(
         ctx,
         user,
         business_id,
         from,
         phone_norm,
         body_text,
         body_stored,
         message_sid,
         jobs_snapshot,
         allowed_job_ids,
         allowed_employee_ids,
         assistant,
         job_ops_raw,
         time_ops_raw,
         emp_ops_raw,
         rem_ops_raw,
         booking_ops_raw,
         body_params
       ) do
    caps = EmployeePermissions.for(user, business_id)

    {job_ops, time_ops, emp_ops, rem_ops} =
      filter_sms_operations_by_permissions(
        job_ops_raw,
        time_ops_raw,
        emp_ops_raw,
        rem_ops_raw,
        caps
      )

    booking_ops_raw =
      booking_ops_raw ++
        SmsBookingInitiateInference.supplement(booking_ops_raw, job_ops_raw, body_text)

    # Booking conversations create clients/links, so gate on job-edit capability.
    booking_ops = if EmployeePermissions.can_edit_jobs?(caps), do: booking_ops_raw, else: []

    had_extracted_ops =
      job_ops_raw != [] or time_ops_raw != [] or emp_ops_raw != [] or rem_ops_raw != [] or
        booking_ops_raw != []

    all_ops = job_ops ++ time_ops ++ emp_ops ++ rem_ops ++ booking_ops

    log_base = %{
      message_sid: message_sid,
      planned_job_ops: job_ops_raw,
      planned_time_ops: time_ops_raw,
      planned_emp_ops: emp_ops_raw,
      planned_reminder_ops: rem_ops_raw,
      planned_booking_ops: booking_ops_raw
    }

    cond do
      all_ops == [] and had_extracted_ops ->
        reply =
          "You don't have permission to apply those changes in this workspace. Ask the business owner to adjust your employee permissions."

        sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply,
          Map.merge(log_base, %{outcome: "permission_denied", results: []})
        )

      all_ops == [] ->
        results =
          append_orphan_mms_attach(
            [],
            business_id,
            phone_norm,
            body_text,
            body_params,
            jobs_snapshot
          )

        if results != [] do
          combined_assistant = first_nonempty([assistant])

          reply =
            SmsReplyBuilder.compose(combined_assistant, results) ||
              "Photo saved."

          record_sms_db_audits(business_id, user.id, %{
            twilio_message_sid: message_sid,
            sms_inbound: body_stored,
            sms_outbound: reply
          }, results)

          sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply,
            Map.merge(log_base, %{outcome: "operations_applied", results: results})
          )
        else
          msg = first_nonempty([assistant])

          reply =
            msg ||
              "No changes applied. Open Romp CRM or include clearer job/time details."

          sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply,
            Map.merge(log_base, %{outcome: "no_db_operations", results: []})
          )
        end

      true ->
        Logger.info(
          "Twilio SMS parsed operations: sid=#{message_sid} count=#{length(all_ops)} from=#{from}"
        )

        job_ctx = %{
          message_sid: message_sid,
          from: from,
          business_id: business_id,
          allowed_job_ids: allowed_job_ids,
          user_id: user.id,
          sms_audit_base: %{
            twilio_message_sid: message_sid,
            sms_inbound: body_stored
          }
        }

        case run_all_operations(
               job_ops,
               time_ops,
               emp_ops,
               rem_ops,
               booking_ops,
               job_ctx,
               allowed_employee_ids
             ) do
          {:clarify, msg} ->
            results =
              append_orphan_mms_attach(
                [],
                business_id,
                phone_norm,
                body_text,
                body_params,
                jobs_snapshot
              )

            if results != [] do
              reply = SmsReplyBuilder.compose(msg, results) || "Photo saved."

              record_sms_db_audits(business_id, user.id, %{
                twilio_message_sid: message_sid,
                sms_inbound: body_stored,
                sms_outbound: reply
              }, results)

              sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply,
                Map.merge(log_base, %{outcome: "operations_applied", results: results})
              )
            else
              sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, msg,
                Map.merge(log_base, %{outcome: "clarify", results: []})
              )
            end

          {:ok, all_results} ->
            all_results =
              append_orphan_mms_attach(
                all_results,
                business_id,
                phone_norm,
                body_text,
                body_params,
                jobs_snapshot
              )

            combined_assistant = first_nonempty([assistant])
            reply = SmsReplyBuilder.compose(combined_assistant, all_results)

            record_sms_db_audits(business_id, user.id, %{
              twilio_message_sid: message_sid,
              sms_inbound: body_stored,
              sms_outbound: reply
            }, all_results)

            sms_reply_and_log(ctx, from, user, business_id, phone_norm, body_stored, reply,
              Map.merge(log_base, %{outcome: "operations_applied", results: all_results})
            )
        end
    end
  end

  defp fill_proposal_media_urls(proposals, mms_urls) when is_list(proposals) do
    Enum.map(proposals, fn %{job_attrs: attrs, attach_media_urls: urls} ->
      urls = if urls == [], do: mms_urls, else: urls
      %{job_attrs: attrs, attach_media_urls: urls}
    end)
  end

  defp default_proposal_reply(proposals) when is_list(proposals) do
    lines =
      proposals
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {%{job_attrs: attrs}, i} ->
        name = Map.get(attrs, :client_name) || Map.get(attrs, "client_name") || "Lead"
        "#{i}) #{name}"
      end)

    "I read #{length(proposals)} lead(s) from the image:\n#{lines}\nReply CONFIRM to create these in Romp CRM."
  end

  defp sms_reply_and_log(
         ctx,
         from,
         user,
         business_id,
         phone_norm,
         inbound_stored_body,
         reply_text,
         _log_extra
       ) do
    if ctx.delivery == :twilio_sms do
      _ = Messages.send_sms(from, reply_text)
    end

    channel = Map.get(ctx, :channel, "sms")
    maybe_record_sms_exchange(business_id, user, phone_norm, inbound_stored_body, reply_text, channel)
    {:ok, reply_text}
  end

  defp append_orphan_mms_attach(results, business_id, phone_norm, body_text, params, jobs_snapshot)
       when is_list(results) and is_list(jobs_snapshot) do
    case SmsMms.maybe_attach_orphan_mms(
           results,
           business_id,
           phone_norm,
           body_text,
           params,
           jobs_snapshot
         ) do
      {:ok, {:photos_saved, %Job{} = job, saved, attempted}} ->
        Logger.info(
          "Twilio SMS orphan MMS attach: business_id=#{business_id} job_id=#{job.id} saved=#{saved}"
        )

        results ++ [{:photos_saved, job, saved, attempted}]

      :skip ->
        results

      {:error, reason} ->
        Logger.warning("Twilio SMS orphan MMS attach failed: #{inspect(reason)}")
        results
    end
  rescue
    e ->
      Logger.error(
        "Twilio SMS orphan MMS attach crashed: business_id=#{business_id} #{Exception.format(:error, e, __STACKTRACE__)}"
      )

      results
  end

  defp filter_sms_operations_by_permissions(job_ops, time_ops, emp_ops, rem_ops, caps) do
    job_ops =
      if EmployeePermissions.can_edit_jobs?(caps), do: job_ops, else: []

    time_ops =
      if EmployeePermissions.can_log_job_time?(caps), do: time_ops, else: []

    emp_ops =
      Enum.filter(emp_ops, fn op ->
        id = emp_op_target_employee_id(op)
        EmployeePermissions.can_log_employee_time?(caps, id)
      end)

    {job_ops, time_ops, emp_ops, rem_ops}
  end

  defp emp_op_target_employee_id({:emp_clock_in_by_id, id, _}), do: id
  defp emp_op_target_employee_id({:emp_clock_out_by_id, id, _}), do: id
  defp emp_op_target_employee_id({:emp_lunch_by_id, id, _, _}), do: id
  defp emp_op_target_employee_id({:emp_log_shift_by_id, id, _, _, _, _}), do: id
  defp emp_op_target_employee_id({:emp_adjust_entry_by_id, _, id, _}), do: id

  defp record_sms_db_audits(business_id, actor_user_id, sms_ctx, results) when is_list(results) do
    base =
      %{
        twilio_message_sid: sms_ctx[:twilio_message_sid] || sms_ctx["twilio_message_sid"],
        sms_inbound: sms_ctx[:sms_inbound] || sms_ctx["sms_inbound"],
        sms_outbound: sms_ctx[:sms_outbound] || sms_ctx["sms_outbound"]
      }

    Enum.each(results, fn r ->
      record_one_sms_audit(business_id, actor_user_id, base, r)
    end)
  end

  defp record_one_sms_audit(bid, uid, base, {:created, %Job{} = job, changes}) do
    audit_sms_entity(bid, uid, "jobs.create", "jobs", job.id, base, %{
      client_name: job.client_name,
      job_id: job.id,
      changes: changes
    })
  end

  defp record_one_sms_audit(bid, uid, base, {:created, %Job{} = job}) do
    job = Jobs.get_job!(job.id, bid)
    record_one_sms_audit(bid, uid, base, {:created, job, Detail.changes_for_job_created(job)})
  end

  defp record_one_sms_audit(bid, uid, base, {:updated, %Job{} = job, fields, changes})
       when is_list(fields) do
    audit_sms_entity(bid, uid, "jobs.update", "jobs", job.id, base, %{
      fields: fields,
      client_name: job.client_name,
      job_id: job.id,
      changes: changes
    })
  end

  defp record_one_sms_audit(bid, uid, base, {:updated, %Job{} = job, fields}) when is_list(fields) do
    record_one_sms_audit(bid, uid, base, {:updated, job, fields, []})
  end

  defp record_one_sms_audit(bid, uid, base, {:time_clocked_in, entry_id, name, at}) do
    audit_sms_entity(bid, uid, "time_entries.create", "time_entries", entry_id, base, %{
      changes: [
        %{type: "time_clocked_in", job_client_name: name, started_at: format_audit_dt(at)}
      ]
    })
  end

  defp record_one_sms_audit(bid, uid, base, {:time_clocked_out, entry_id, name, started_at, ended_at}) do
    audit_sms_entity(bid, uid, "time_entries.update", "time_entries", entry_id, base, %{
      changes: [
        %{
          type: "time_clocked_out",
          job_client_name: name,
          started_at: format_audit_dt(started_at),
          ended_at: format_audit_dt(ended_at)
        }
      ]
    })
  end

  defp record_one_sms_audit(_, _, _, {:emp_clocked_in, _, _, _}), do: :ok
  defp record_one_sms_audit(_, _, _, {:emp_clocked_out, _, _, _, _}), do: :ok
  defp record_one_sms_audit(_, _, _, {:emp_lunched, _, _, _, _}), do: :ok
  defp record_one_sms_audit(_, _, _, {:emp_shift_logged, _, _, _, _, _}), do: :ok
  defp record_one_sms_audit(_, _, _, {:emp_adjusted, _, _}), do: :ok

  defp record_one_sms_audit(bid, uid, base, {:photos_saved, %Job{} = job, saved, attempted}) do
    audit_sms_entity(bid, uid, "job_photos.create", "jobs", job.id, base, %{
      client_name: job.client_name,
      job_id: job.id,
      changes: [%{type: "photos_attached", saved: saved, attempted: attempted}]
    })
  end

  defp record_one_sms_audit(bid, uid, base, {:reminder_created, %Reminder{} = r}) do
    audit_sms_entity(bid, uid, "reminders.create", "reminders", r.id, base, %{
      job_id: r.job_id,
      changes: [
        %{
          type: "reminder_scheduled",
          body: r.body,
          fire_at: DateTime.to_iso8601(r.fire_at)
        }
      ]
    })
  end

  defp record_one_sms_audit(_, _, _, _), do: :ok

  defp audit_sms_entity(bid, uid, action, entity_type, entity_id, base, extra) when is_map(extra) do
    BusinessAuditLogs.record(%{
      business_id: bid,
      actor_user_id: uid,
      source: "sms",
      action: action,
      entity_type: entity_type,
      entity_id: entity_id,
      metadata: Map.merge(base, extra)
    })
  end

  defp format_audit_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_audit_dt(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_audit_dt(other), do: inspect(other)

  defp maybe_record_sms_exchange(business_id, user, phone_norm, inbound_body, outbound_body, channel)
       when is_binary(phone_norm) and phone_norm != "" do
    case SmsConversations.record_exchange(
           business_id,
           user.id,
           phone_norm,
           inbound_body,
           outbound_body,
           channel: channel
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS: could not persist conversation log business_id=#{business_id} reason=#{inspect(reason)}"
        )
    end
  end

  defp maybe_record_sms_exchange(_, _, "", _, _, _), do: :ok

  # Runs all operation lists and collects results. Job fuzzy-match errors trigger clarification.
  defp run_all_operations(job_ops, time_ops, emp_ops, rem_ops, booking_ops, job_ctx, allowed_employee_ids) do
    with {:ok, job_results} <- run_job_operations(job_ops, job_ctx),
         {:ok, time_results} <- run_time_operations(time_ops, job_ctx),
         {:ok, emp_results} <-
           run_emp_operations(
             emp_ops,
             job_ctx.message_sid,
             job_ctx.from,
             job_ctx.business_id,
             allowed_employee_ids,
             job_ctx.user_id,
             Map.get(job_ctx, :sms_audit_base, %{})
           ),
         {:ok, rem_results} <- run_reminder_operations(rem_ops, job_ctx),
         {:ok, booking_results} <-
           Bookings.Orchestrator.run_operations(booking_ops, %{
             business_id: job_ctx.business_id,
             user_id: job_ctx.user_id,
             message_sid: job_ctx.message_sid,
             # Jobs created by this same message, so "add the lead and schedule
             # with her" links the booking to the new job/client (no duplicates).
             created_jobs: for({:created, %Job{} = job, _} <- job_results, do: job)
           }) do
      {:ok, job_results ++ time_results ++ emp_results ++ rem_results ++ booking_results}
    end
  end

  # ── Job operations (existing) ────────────────────────────────────────────

  defp run_job_operations(ops, ctx) do
    Enum.reduce_while(Enum.with_index(ops, 1), [], fn {op, idx}, acc ->
      case apply_sms_operation_ret(
             op,
             idx,
             ctx.message_sid,
             ctx.from,
             ctx.business_id,
             ctx.allowed_job_ids
           ) do
        {:clarify_match, msg} ->
          {:halt, {:clarify, msg}}

        other ->
          {:cont, [other | acc]}
      end
    end)
    |> case do
      {:clarify, msg} -> {:clarify, msg}
      rev when is_list(rev) -> {:ok, Enum.reverse(rev)}
    end
  end

  # ── Time tracking operations ──────────────────────────────────────────────

  defp run_time_operations(ops, ctx) do
    results =
      ops
      |> Enum.with_index(1)
      |> Enum.map(fn {op, idx} ->
        apply_time_operation(
          op,
          idx,
          ctx.message_sid,
          ctx.from,
          ctx.business_id,
          ctx.allowed_job_ids
        )
      end)

    {:ok, results}
  end

  defp apply_time_operation(
         {:clock_in_by_id, job_id, started_at},
         idx,
         sid,
         from,
         business_id,
         allowed_ids
       ) do
    Logger.info(
      "Twilio SMS time clock_in: sid=#{sid} from=#{from} op_index=#{idx} job_id=#{job_id} started_at=#{started_at}"
    )

    if not MapSet.member?(allowed_ids, job_id) do
      Logger.info(
        "Twilio SMS time_clock_in skipped: sid=#{sid} op_index=#{idx} reason=:invalid_job_id job_id=#{job_id}"
      )

      {:skipped, :invalid_job_id}
    else
      case Jobs.get_job(job_id, business_id) do
        nil ->
          Logger.info(
            "Twilio SMS time_clock_in skipped: sid=#{sid} op_index=#{idx} reason=:job_not_found job_id=#{job_id}"
          )

          {:skipped, :job_not_found}

        job ->
          case TimeTracking.create_time_entry(%{
                 business_id: business_id,
                 job_id: job.id,
                 started_at: started_at
               }) do
            {:ok, entry} ->
              Logger.info(
                "Twilio SMS time_clock_in applied: sid=#{sid} op_index=#{idx} job_id=#{job.id} entry_id=#{entry.id}"
              )

              {:time_clocked_in, entry.id, job.client_name, started_at}

            {:error, cs} ->
              Logger.warning(
                "Twilio SMS time_clock_in failed: sid=#{sid} op_index=#{idx} job_id=#{job.id} errors=#{inspect(cs.errors)}"
              )

              {:error, :clock_in_failed}
          end
      end
    end
  end

  defp apply_time_operation(
         {:clock_out_by_id, job_id, ended_at},
         idx,
         sid,
         from,
         business_id,
         allowed_ids
       ) do
    Logger.info(
      "Twilio SMS time clock_out: sid=#{sid} from=#{from} op_index=#{idx} job_id=#{job_id} ended_at=#{ended_at}"
    )

    if not MapSet.member?(allowed_ids, job_id) do
      Logger.info(
        "Twilio SMS time_clock_out skipped: sid=#{sid} op_index=#{idx} reason=:invalid_job_id job_id=#{job_id}"
      )

      {:skipped, :invalid_job_id}
    else
      case TimeTracking.get_open_entry_for_job(job_id, business_id) do
        nil ->
          Logger.info(
            "Twilio SMS time_clock_out skipped: sid=#{sid} op_index=#{idx} reason=:no_open_entry job_id=#{job_id}"
          )

          {:skipped, :no_open_entry}

        entry ->
          case TimeTracking.update_time_entry(entry, %{ended_at: ended_at}) do
            {:ok, updated} ->
              Logger.info(
                "Twilio SMS time_clock_out applied: sid=#{sid} op_index=#{idx} job_id=#{job_id} entry_id=#{updated.id}"
              )

              job = Jobs.get_job(job_id, business_id)
              {:time_clocked_out, updated.id, job && job.client_name, updated.started_at, ended_at}

            {:error, cs} ->
              Logger.warning(
                "Twilio SMS time_clock_out failed: sid=#{sid} op_index=#{idx} job_id=#{job_id} errors=#{inspect(cs.errors)}"
              )

              {:error, :clock_out_failed}
          end
      end
    end
  end

  # ── Employee time operations ──────────────────────────────────────────────

  defp run_emp_operations(ops, sid, from, business_id, allowed_ids, actor_user_id, audit_base) do
    results =
      ops
      |> Enum.with_index(1)
      |> Enum.map(fn {op, idx} ->
        apply_emp_operation(op, idx, sid, from, business_id, allowed_ids, actor_user_id, audit_base)
      end)

    {:ok, results}
  end

  defp apply_emp_operation(op, idx, sid, from, business_id, allowed_ids, actor_user_id, audit_base) do
    emp_id = emp_op_target_employee_id(op)
    audit_opts = [audit_extra: Map.put(audit_base, :sms_outbound, nil)]

    Logger.info(
      "Twilio SMS emp op: sid=#{sid} from=#{from} op_index=#{idx} employee_id=#{inspect(emp_id)} op=#{inspect(op)}"
    )

    if not MapSet.member?(allowed_ids, emp_id) do
      {:skipped, :invalid_employee_id}
    else
      case Employees.get_employee(emp_id, business_id) do
        nil ->
          {:skipped, :employee_not_found}

        emp ->
          apply_emp_operation_for_employee(
            op,
            emp,
            business_id,
            actor_user_id,
            audit_opts,
            sid,
            idx
          )
      end
    end
  end

  defp apply_emp_operation_for_employee(
         {:emp_clock_in_by_id, _emp_id, clocked_in_at},
         emp,
         business_id,
         actor_user_id,
         audit_opts,
         sid,
         idx
       ) do
    case TimeEntryActions.sms_clock_in(business_id, actor_user_id, emp, clocked_in_at, audit_opts) do
      {:ok, entry} ->
        Logger.info("Twilio SMS emp_clock_in applied: sid=#{sid} op_index=#{idx} entry_id=#{entry.id}")
        {:emp_clocked_in, entry.id, emp.name, clocked_in_at}

      {:error, :already_clocked_in, _} ->
        {:skipped, :already_clocked_in}

      {:error, _} ->
        {:error, :emp_clock_in_failed}
    end
  end

  defp apply_emp_operation_for_employee(
         {:emp_clock_out_by_id, _emp_id, clocked_out_at},
         emp,
         business_id,
         actor_user_id,
         audit_opts,
         sid,
         idx
       ) do
    case TimeEntryActions.sms_clock_out(business_id, actor_user_id, emp, clocked_out_at, audit_opts) do
      {:ok, updated} ->
        Logger.info("Twilio SMS emp_clock_out applied: sid=#{sid} op_index=#{idx} entry_id=#{updated.id}")
        {:emp_clocked_out, updated.id, emp.name, updated.clocked_in_at, clocked_out_at}

      {:error, :no_open_entry} ->
        {:skipped, :no_open_entry}

      {:error, _} ->
        {:error, :emp_clock_out_failed}
    end
  end

  defp apply_emp_operation_for_employee(
         {:emp_lunch_by_id, _emp_id, lunch_start, lunch_end},
         emp,
         business_id,
         actor_user_id,
         audit_opts,
         sid,
         idx
       ) do
    case TimeEntryActions.sms_lunch(business_id, actor_user_id, emp, lunch_start, lunch_end, audit_opts) do
      {:ok, updated} ->
        Logger.info("Twilio SMS emp_lunch applied: sid=#{sid} op_index=#{idx}")
        {:emp_lunched, updated.id, emp.name, lunch_start, lunch_end}

      {:error, :no_open_entry} ->
        {:skipped, :no_open_entry}

      {:error, _} ->
        {:error, :emp_lunch_failed}
    end
  end

  defp apply_emp_operation_for_employee(
         {:emp_log_shift_by_id, _emp_id, tin, tout, ls, le},
         emp,
         business_id,
         actor_user_id,
         audit_opts,
         sid,
         idx
       ) do
    attrs = %{
      clocked_in_at: tin,
      clocked_out_at: tout,
      lunch_start_at: ls,
      lunch_end_at: le
    }

    extra = Keyword.get(audit_opts, :audit_extra, %{})

    case TimeEntryActions.create_shift(business_id, actor_user_id, emp, attrs,
           via: :sms,
           clock_in_kind: :sms_shift,
           clock_out_kind: :sms_shift,
           audit_extra: extra
         ) do
      {:ok, entry} ->
        Logger.info("Twilio SMS emp_log_shift applied: sid=#{sid} op_index=#{idx} entry_id=#{entry.id}")
        {:emp_shift_logged, entry.id, emp.name, tin, tout}

      {:error, _} ->
        {:error, :emp_log_shift_failed}
    end
  end

  defp apply_emp_operation_for_employee(
         {:emp_adjust_entry_by_id, entry_id, _emp_id, patch},
         emp,
         business_id,
         actor_user_id,
         audit_opts,
         sid,
         idx
       ) do
    try do
      entry = Employees.get_time_entry!(entry_id, business_id)

      if entry.employee_id != emp.id do
        {:skipped, :entry_employee_mismatch}
      else
        extra = Keyword.get(audit_opts, :audit_extra, %{})

        case TimeEntryActions.adjust_entry(business_id, actor_user_id, emp, entry, patch,
               via: :sms,
               audit_extra: extra
             ) do
          {:ok, updated} ->
            Logger.info("Twilio SMS emp_adjust applied: sid=#{sid} op_index=#{idx} entry_id=#{updated.id}")
            {:emp_adjusted, updated.id, emp.name}

          {:error, _} ->
            {:error, :emp_adjust_failed}
        end
      end
    rescue
      Ecto.NoResultsError ->
        {:skipped, :entry_not_found}
    end
  end

  # ── Reminders (SMS-scheduled rows; not gated by job/time employee permissions) ──

  defp run_reminder_operations([], _ctx), do: {:ok, []}

  defp run_reminder_operations(ops, ctx) do
    results =
      ops
      |> Enum.with_index(1)
      |> Enum.map(fn {op, idx} -> apply_reminder_op(op, idx, ctx) end)

    {:ok, results}
  end

  defp apply_reminder_op(
         {:reminder_schedule, %DateTime{} = fire_at, body, job_id, meta},
         idx,
         %{message_sid: sid, from: from, business_id: business_id, allowed_job_ids: allowed, user_id: user_id}
       ) do
    Logger.info(
      "Twilio SMS reminder schedule: sid=#{sid} from=#{from} op_index=#{idx} user_id=#{user_id} job_id=#{inspect(job_id)}"
    )

    verified_job_id =
      cond do
        is_nil(job_id) ->
          nil

        not MapSet.member?(allowed, job_id) ->
          :invalid

        Jobs.get_job(job_id, business_id) == nil ->
          :invalid

        true ->
          job_id
      end

    cond do
      verified_job_id == :invalid ->
        Logger.info(
          "Twilio SMS reminder skipped: sid=#{sid} op_index=#{idx} reason=:invalid_job_id job_id=#{inspect(job_id)}"
        )

        {:skipped, :invalid_job_id}

      true ->
        meta = if is_map(meta), do: meta, else: %{}

        attrs = %{
          user_id: user_id,
          business_id: business_id,
          job_id: verified_job_id,
          body: body,
          fire_at: DateTime.truncate(fire_at, :second),
          source: "sms",
          metadata_json: Jason.encode!(meta)
        }

        case Reminders.create_reminder(attrs) do
          {:ok, %Reminder{} = r} ->
            Logger.info("Twilio SMS reminder created: sid=#{sid} reminder_id=#{r.id}")
            {:reminder_created, r}

          {:error, cs} ->
            Logger.warning("Twilio SMS reminder insert failed: #{inspect(cs.errors)}")
            {:error, :reminder_create_failed}
        end
    end
  end

  # ── Job photos (MMS) ─────────────────────────────────────────────────────

  defp apply_sms_operation_ret(
         {:attach_photos, job_id, work_item_title_hint, urls},
         idx,
         message_sid,
         from,
         business_id,
         allowed_job_ids
       )
       when is_list(urls) do
    Logger.info(
      "Twilio SMS attach_photos: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job_id} count=#{length(urls)}"
    )

    cond do
      not MapSet.member?(allowed_job_ids, job_id) ->
        Logger.info(
          "Twilio SMS attach_photos skipped: sid=#{message_sid} op_index=#{idx} reason=:invalid_job_id job_id=#{job_id}"
        )

        {:skipped, :invalid_job_id}

      true ->
        case Jobs.get_job(job_id, business_id) do
          nil ->
            Logger.info(
              "Twilio SMS attach_photos skipped: sid=#{message_sid} op_index=#{idx} reason=:job_not_found job_id=#{job_id}"
            )

            {:skipped, :job_not_found}

          job ->
            wi_id =
              case work_item_title_hint do
                nil -> nil
                "" -> nil
                hint -> Jobs.find_work_item_id_by_title_substring(job, hint)
              end

            results = Enum.map(urls, fn url -> Jobs.add_job_photo_from_url(job, business_id, url, wi_id) end)

            ok_ct = Enum.count(results, &match?({:ok, %RompCrm.Jobs.JobPhoto{}}, &1))
            skip_ct = Enum.count(results, &match?({:ok, :duplicate_skipped}, &1))

            if ok_ct > 0 or skip_ct == length(urls) do
              Logger.info(
                "Twilio SMS attach_photos applied: sid=#{message_sid} op_index=#{idx} job_id=#{job.id} saved=#{ok_ct} skipped=#{skip_ct}/#{length(urls)}"
              )

              {:photos_saved, job, ok_ct, length(urls)}
            else
              Logger.warning(
                "Twilio SMS attach_photos failed: sid=#{message_sid} op_index=#{idx} job_id=#{job.id} results=#{inspect(results)}"
              )

              {:error, :attach_photo_all_failed}
            end
        end
    end
  end

  defp apply_sms_operation_ret(
         {:create, attrs},
         idx,
         message_sid,
         from,
         business_id,
         _allowed_job_ids
       ) do
    Logger.info(
      "Twilio SMS parsed create: sid=#{message_sid} from=#{from} op_index=#{idx} attrs=#{inspect(attrs)}"
    )

    attrs =
      attrs
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
      |> Map.put("business_id", business_id)

    case Jobs.create_job(attrs) do
      {:ok, %Job{} = job} ->
        job =
          case Clients.finalize_job_client_link(job, attrs) do
            {:ok, linked} -> linked
            _ -> job
          end

        job = Jobs.get_job!(job.id, business_id)
        changes = Detail.changes_for_job_created(job)

        Logger.info(
          "Twilio SMS create applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id}"
        )

        {:created, job, changes}

      {:error, changeset} ->
        Logger.warning(
          "Twilio SMS create failed: sid=#{message_sid} from=#{from} op_index=#{idx} errors=#{inspect(changeset.errors)}"
        )

        {:error, :create_failed}
    end
  end

  defp apply_sms_operation_ret(
         {:update_by_id, job_id, patch},
         idx,
         message_sid,
         from,
         business_id,
         allowed_job_ids
       ) do
    Logger.info(
      "Twilio SMS parsed update: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job_id} patch=#{inspect(patch)}"
    )

    cond do
      not MapSet.member?(allowed_job_ids, job_id) ->
        Logger.info(
          "Twilio SMS update skipped: sid=#{message_sid} from=#{from} op_index=#{idx} reason=:invalid_job_id job_id=#{job_id} patch=#{inspect(patch)}"
        )

        {:skipped, :invalid_job_id}

      true ->
        case Jobs.get_job(job_id, business_id) do
          nil ->
            Logger.info(
              "Twilio SMS update skipped: sid=#{message_sid} from=#{from} op_index=#{idx} reason=:job_not_found job_id=#{job_id}"
            )

            {:skipped, :job_not_found}

          job ->
            patch = Enum.into(patch, %{}, fn {k, v} -> {to_string(k), v} end)
            before_snap = Detail.job_snapshot(job)

            case Jobs.update_job(job, patch) do
              {:ok, %Job{} = updated_job} ->
                updated_job = Jobs.get_job!(updated_job.id, business_id)
                after_snap = Detail.job_snapshot(updated_job)

                changes =
                  Detail.changes_from_job_patch(job, patch, before_snap, after_snap)

                Logger.info(
                  "Twilio SMS update applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{updated_job.id} changed_fields=#{inspect(Map.keys(patch))}"
                )

                {:updated, updated_job, Map.keys(patch), changes}

              {:error, changeset} ->
                Logger.warning(
                  "Twilio SMS update failed: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id} errors=#{inspect(changeset.errors)}"
                )

                {:error, :update_failed}
            end
        end
    end
  end

  defp apply_sms_operation_ret(
         {:update, match, patch},
         idx,
         message_sid,
         from,
         business_id,
         _allowed_job_ids
       ) do
    Logger.info(
      "Twilio SMS parsed update: sid=#{message_sid} from=#{from} op_index=#{idx} match=#{inspect(match)} patch=#{inspect(patch)}"
    )

    patch = Enum.into(patch, %{}, fn {k, v} -> {to_string(k), v} end)

    case Jobs.find_job_for_sms_update(match, business_id) do
      {:ok, job} ->
        before_snap = Detail.job_snapshot(job)

        case Jobs.update_job(job, patch) do
          {:ok, %Job{} = updated_job} ->
            updated_job = Jobs.get_job!(updated_job.id, business_id)
            after_snap = Detail.job_snapshot(updated_job)

            changes =
              Detail.changes_from_job_patch(job, patch, before_snap, after_snap)

            Logger.info(
              "Twilio SMS update applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{updated_job.id} changed_fields=#{inspect(Map.keys(patch))}"
            )

            {:updated, updated_job, Map.keys(patch), changes}

          {:error, changeset} ->
            Logger.warning(
              "Twilio SMS update failed: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id} errors=#{inspect(changeset.errors)}"
            )

            {:error, :update_failed}
        end

      {:error, :ambiguous} ->
        msg = Jobs.ambiguous_match_clarification_sms(match, business_id)
        {:clarify_match, msg}

      {:error, reason} ->
        Logger.info(
          "Twilio SMS update skipped: sid=#{message_sid} from=#{from} op_index=#{idx} reason=#{inspect(reason)} match=#{inspect(match)} patch=#{inspect(patch)}"
        )

        {:skipped, reason}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp sms_extraction_failed_reply(:missing_api_key) do
    "SMS AI isn't configured on this server. Please use Romp CRM in the browser."
  end

  defp sms_extraction_failed_reply(:empty_extract) do
    "Couldn't understand that message. Try again or open Romp CRM."
  end

  defp sms_extraction_failed_reply({:invalid_action, _, _}) do
    "Couldn't apply one of the actions in that text. Open Romp CRM or simplify the message."
  end

  defp sms_extraction_failed_reply({:invalid_reminder_action, _, _}) do
    "Couldn't parse a reminder in that text. Open Romp CRM or say the date/time more explicitly."
  end

  defp sms_extraction_failed_reply({:anthropic_http, status, _}) when is_integer(status) do
    "Assistant unavailable (#{status}). Try again in a moment."
  end

  defp sms_extraction_failed_reply({:request, _}) do
    "Couldn't reach the assistant. Try again shortly."
  end

  defp sms_extraction_failed_reply(:invalid_json_from_model) do
    "Got an unreadable reply from the assistant. Please try again."
  end

  defp sms_extraction_failed_reply(:invalid_actions) do
    "Invalid action list from the assistant. Open Romp CRM."
  end

  defp sms_extraction_failed_reply(_reason) do
    "Couldn't parse that SMS. Open Romp CRM or try again."
  end

  defp first_nonempty(list) do
    Enum.find(list, fn s -> is_binary(s) and String.trim(s) != "" end)
  end

end
