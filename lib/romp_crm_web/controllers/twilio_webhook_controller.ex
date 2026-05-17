defmodule RompCrmWeb.TwilioWebhookController do
  use RompCrmWeb, :controller

  require Logger

  alias RompCrm.Accounts
  alias RompCrm.Ai.SmsUnifiedInboundExtractor
  alias RompCrm.BusinessAuditLogs
  alias RompCrm.BusinessAuditLogs.Detail
  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Employees
  alias RompCrm.Jobs
  alias RompCrm.Reminders
  alias RompCrm.Jobs.Job
  alias RompCrm.Reminders.Reminder
  alias RompCrm.SmsConversations
  alias RompCrm.TimeTracking
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone
  alias RompCrm.Twilio.Signature
  alias RompCrm.Twilio.SmsReplyBuilder

  @doc """
  Twilio `POST` webhook for inbound SMS. Configure the number's "A message comes in"
  URL to `https://YOUR_HOST/webhooks/twilio/sms` with HTTP POST.
  """
  def sms(conn, _params) do
    skip? = Application.get_env(:romp_crm, :skip_twilio_signature_validation, false)
    token = Application.get_env(:romp_crm, :twilio_auth_token)
    public_url = Application.get_env(:romp_crm, :twilio_webhook_public_url)

    cond do
      not skip? and (is_nil(token) or token == "") ->
        Logger.warning(
          "Twilio SMS webhook rejected: set TWILIO_AUTH_TOKEN or enable skip for dev"
        )

        send_resp(conn, 503, "Not configured")

      not skip? and not Signature.valid?(conn, token, public_url: public_url) ->
        send_resp(conn, 403, "Forbidden")

      true ->
        maybe_deliver_inbound_sms(conn)
    end
  end

  @doc """
  Twilio **voice** webhook: returns TwiML that dials the configured support PSTN number.

  Configure the Twilio number’s **“A call comes in”** URL to `https://YOUR_HOST/.../webhooks/twilio/voice`
  (POST or GET). This does **not** change SMS handling (`/webhooks/twilio/sms`).
  """
  def voice(conn, _params) do
    merged = Map.merge(conn.query_params || %{}, conn.body_params || %{})
    conn_sig = %{conn | body_params: merged}

    skip? = Application.get_env(:romp_crm, :skip_twilio_signature_validation, false)
    token = Application.get_env(:romp_crm, :twilio_auth_token)
    public_url = voice_webhook_public_url()

    cond do
      not skip? and (is_nil(token) or token == "") ->
        Logger.warning(
          "Twilio Voice webhook rejected: set TWILIO_AUTH_TOKEN or enable skip for dev"
        )

        send_resp(conn, 503, "Not configured")

      not skip? and not Signature.valid?(conn_sig, token, public_url: public_url) ->
        send_resp(conn, 403, "Forbidden")

      true ->
        forward_to =
          Application.get_env(:romp_crm, :twilio_voice_forward_e164, "+18024587299")

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, voice_twiml_dial(forward_to))
    end
  end

  defp voice_webhook_public_url do
    case Application.get_env(:romp_crm, :twilio_voice_webhook_public_url) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        infer_voice_url_from_sms_webhook()
    end
  end

  defp infer_voice_url_from_sms_webhook do
    case Application.get_env(:romp_crm, :twilio_webhook_public_url) do
      url when is_binary(url) and url != "" ->
        cond do
          String.ends_with?(url, "/sms") -> String.replace_suffix(url, "/sms", "/voice")
          String.ends_with?(url, "/sms/") -> String.replace_suffix(url, "/sms/", "/voice")
          true -> String.trim_trailing(url, "/") <> "/voice"
        end

      _ ->
        nil
    end
  end

  defp voice_twiml_dial(e164) when is_binary(e164) do
    # PSTN forward; `answerOnBridge` avoids dead air while the callee’s phone rings.
    ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Dial answerOnBridge="true">#{e164}</Dial></Response>)
  end

  defp maybe_deliver_inbound_sms(conn) do
    from = conn.body_params["From"] |> to_string()
    norm = Phone.normalize_us(from)
    message_sid = conn.body_params["MessageSid"] |> to_string()

    cond do
      norm == "" ->
        Logger.info("Twilio SMS: empty From after normalize sid=#{message_sid}")
        twiml_ok(conn)

      true ->
        case Accounts.get_user_by_phone_normalized(norm) do
          nil ->
            Logger.info(
              "Twilio SMS: no user with profile phone matching from=#{inspect(from)} sid=#{message_sid}"
            )

            twiml_ok(conn)

          user ->
            case Businesses.resolve_sms_business_id(user) do
              {:ok, business_id} ->
                deliver_inbound_sms(conn, user, business_id)

              {:error, :no_membership} ->
                Logger.warning(
                  "Twilio SMS: user id=#{user.id} has no business membership sid=#{message_sid}"
                )

                twiml_ok(conn)

              {:error, :ambiguous_sms_routing} ->
                Logger.warning(
                  "Twilio SMS: user id=#{user.id} belongs to multiple businesses; set a workspace in the Jobs picker or SMS workspace in Settings sid=#{message_sid}"
                )

                maybe_reply_routing_help(from)
                twiml_ok(conn)
            end
        end
    end
  end

  defp maybe_reply_routing_help(from) do
    reply =
      "Pick a workspace in Romp CRM (jobs picker), then text again—or set SMS workspace in Settings."

    _ = Messages.send_sms(from, reply)
    :ok
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

  defp deliver_inbound_sms(conn, user, business_id) do
    body_text = (conn.body_params["Body"] || "") |> to_string()
    body_for_ai = inbound_sms_body_for_extraction(body_text, conn.body_params)
    from = conn.body_params["From"] |> to_string()
    to_num = conn.body_params["To"] |> to_string()
    message_sid = conn.body_params["MessageSid"] |> to_string()
    phone_norm = Phone.normalize_us(from)

    Logger.info(
      "Twilio SMS inbound: sid=#{message_sid} to=#{inspect(to_num)} user_id=#{user.id} business_id=#{business_id} from=#{from} body=#{inspect(body_text)}"
    )

    jobs_snapshot = Jobs.snapshot_for_sms_ai(business_id)
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

    case SmsUnifiedInboundExtractor.extract(
           body_for_ai,
           jobs_snapshot,
           open_time_entries,
           employees_snapshot,
           prior_turns,
           reminder_wall_tz: reminder_wall_tz
         ) do
      {:ok,
       %{
         assistant_sms: assistant,
         job_operations: job_ops_raw,
         time_operations: time_ops_raw,
         emp_operations: emp_ops_raw,
         reminder_operations: rem_ops_raw
       }} ->
        caps = EmployeePermissions.for(user, business_id)

        {job_ops, time_ops, emp_ops, rem_ops} =
          filter_sms_operations_by_permissions(
            job_ops_raw,
            time_ops_raw,
            emp_ops_raw,
            rem_ops_raw,
            caps
          )

        had_extracted_ops =
          job_ops_raw != [] or time_ops_raw != [] or emp_ops_raw != [] or rem_ops_raw != []

        all_ops = job_ops ++ time_ops ++ emp_ops ++ rem_ops

        log_base = %{
          message_sid: message_sid,
          planned_job_ops: job_ops_raw,
          planned_time_ops: time_ops_raw,
          planned_emp_ops: emp_ops_raw,
          planned_reminder_ops: rem_ops_raw
        }

        cond do
          all_ops == [] and had_extracted_ops ->
            reply =
              "You don't have permission to apply those changes in this workspace. Ask the business owner to adjust your employee permissions."

            sms_reply_and_log(conn, from, user, business_id, phone_norm, body_text, reply,
              Map.merge(log_base, %{outcome: "permission_denied", results: []})
            )

          all_ops == [] ->
            msg = first_nonempty([assistant])

            reply =
              msg ||
                "No changes applied. Open Romp CRM or include clearer job/time details."

            sms_reply_and_log(conn, from, user, business_id, phone_norm, body_text, reply,
              Map.merge(log_base, %{outcome: "no_db_operations", results: []})
            )

          true ->
            Logger.info(
              "Twilio SMS parsed operations: sid=#{message_sid} count=#{length(all_ops)} from=#{from}"
            )

            job_ctx = %{
              message_sid: message_sid,
              from: from,
              business_id: business_id,
              allowed_job_ids: allowed_job_ids,
              user_id: user.id
            }

            case run_all_operations(
                   job_ops,
                   time_ops,
                   emp_ops,
                   rem_ops,
                   job_ctx,
                   allowed_employee_ids
                 ) do
              {:clarify, msg} ->
                sms_reply_and_log(conn, from, user, business_id, phone_norm, body_text, msg,
                  Map.merge(log_base, %{outcome: "clarify", results: []})
                )

              {:ok, all_results} ->
                combined_assistant = first_nonempty([assistant])
                reply = SmsReplyBuilder.compose(combined_assistant, all_results)

                record_sms_db_audits(business_id, user.id, %{
                  twilio_message_sid: message_sid,
                  sms_inbound: body_text,
                  sms_outbound: reply
                }, all_results)

                sms_reply_and_log(conn, from, user, business_id, phone_norm, body_text, reply,
                  Map.merge(log_base, %{outcome: "operations_applied", results: all_results})
                )
            end
        end

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS unified extraction failed: sid=#{message_sid} from=#{from} reason=#{inspect(reason)}"
        )

        reply = sms_extraction_failed_reply(reason)

        sms_reply_and_log(conn, from, user, business_id, phone_norm, body_text, reply, %{
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

  defp sms_reply_and_log(
         conn,
         from,
         user,
         business_id,
         phone_norm,
         inbound_body,
         reply_text,
         _log_extra
       ) do
    _ = Messages.send_sms(from, reply_text)
    maybe_record_sms_exchange(business_id, user, phone_norm, inbound_body, reply_text)
    twiml_ok(conn)
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

  defp record_one_sms_audit(bid, uid, base, {:emp_clocked_in, entry_id, emp_name, at}) do
    audit_sms_entity(bid, uid, "employee_time_entries.create", "employee_time_entries", entry_id, base, %{
      changes: [
        %{type: "employee_time", action: "clock_in", employee_name: emp_name, at: format_audit_dt(at)}
      ]
    })
  end

  defp record_one_sms_audit(bid, uid, base, {:emp_clocked_out, entry_id, emp_name, tin, tout}) do
    audit_sms_entity(bid, uid, "employee_time_entries.update", "employee_time_entries", entry_id, base, %{
      changes: [
        %{
          type: "employee_time",
          action: "clock_out",
          employee_name: emp_name,
          clocked_in_at: format_audit_dt(tin),
          clocked_out_at: format_audit_dt(tout)
        }
      ]
    })
  end

  defp record_one_sms_audit(bid, uid, base, {:emp_lunched, entry_id, emp_name, ls, le}) do
    audit_sms_entity(bid, uid, "employee_time_entries.update", "employee_time_entries", entry_id, base, %{
      changes: [
        %{
          type: "employee_time",
          action: "lunch",
          employee_name: emp_name,
          lunch_start_at: format_audit_dt(ls),
          lunch_end_at: format_audit_dt(le)
        }
      ]
    })
  end

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

  defp maybe_record_sms_exchange(business_id, user, phone_norm, inbound_body, outbound_body)
       when is_binary(phone_norm) and phone_norm != "" do
    case SmsConversations.record_exchange(
           business_id,
           user.id,
           phone_norm,
           inbound_body,
           outbound_body
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS: could not persist conversation log business_id=#{business_id} reason=#{inspect(reason)}"
        )
    end
  end

  defp maybe_record_sms_exchange(_, _, "", _, _), do: :ok

  # Runs all operation lists and collects results. Job fuzzy-match errors trigger clarification.
  defp run_all_operations(job_ops, time_ops, emp_ops, rem_ops, job_ctx, allowed_employee_ids) do
    with {:ok, job_results} <- run_job_operations(job_ops, job_ctx),
         {:ok, time_results} <- run_time_operations(time_ops, job_ctx),
         {:ok, emp_results} <-
           run_emp_operations(
             emp_ops,
             job_ctx.message_sid,
             job_ctx.from,
             job_ctx.business_id,
             allowed_employee_ids
           ),
         {:ok, rem_results} <- run_reminder_operations(rem_ops, job_ctx) do
      {:ok, job_results ++ time_results ++ emp_results ++ rem_results}
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

  defp run_emp_operations(ops, sid, from, business_id, allowed_ids) do
    results =
      ops
      |> Enum.with_index(1)
      |> Enum.map(fn {op, idx} ->
        apply_emp_operation(op, idx, sid, from, business_id, allowed_ids)
      end)

    {:ok, results}
  end

  defp apply_emp_operation(
         {:emp_clock_in_by_id, emp_id, clocked_in_at},
         idx,
         sid,
         from,
         business_id,
         allowed_ids
       ) do
    Logger.info(
      "Twilio SMS emp clock_in: sid=#{sid} from=#{from} op_index=#{idx} employee_id=#{emp_id}"
    )

    if not MapSet.member?(allowed_ids, emp_id) do
      Logger.info(
        "Twilio SMS emp_clock_in skipped: sid=#{sid} op_index=#{idx} reason=:invalid_employee_id employee_id=#{emp_id}"
      )

      {:skipped, :invalid_employee_id}
    else
      case Employees.get_employee(emp_id, business_id) do
        nil ->
          Logger.info(
            "Twilio SMS emp_clock_in skipped: sid=#{sid} reason=:employee_not_found employee_id=#{emp_id}"
          )

          {:skipped, :employee_not_found}

        emp ->
          case Employees.create_time_entry(%{
                 business_id: business_id,
                 employee_id: emp.id,
                 clocked_in_at: clocked_in_at
               }) do
            {:ok, entry} ->
              Logger.info(
                "Twilio SMS emp_clock_in applied: sid=#{sid} employee_id=#{emp.id} entry_id=#{entry.id}"
              )

              {:emp_clocked_in, entry.id, emp.name, clocked_in_at}

            {:error, cs} ->
              Logger.warning("Twilio SMS emp_clock_in failed: #{inspect(cs.errors)}")
              {:error, :emp_clock_in_failed}
          end
      end
    end
  end

  defp apply_emp_operation(
         {:emp_clock_out_by_id, emp_id, clocked_out_at},
         idx,
         sid,
         from,
         business_id,
         allowed_ids
       ) do
    Logger.info(
      "Twilio SMS emp clock_out: sid=#{sid} from=#{from} op_index=#{idx} employee_id=#{emp_id}"
    )

    if not MapSet.member?(allowed_ids, emp_id) do
      Logger.info(
        "Twilio SMS emp_clock_out skipped: sid=#{sid} reason=:invalid_employee_id employee_id=#{emp_id}"
      )

      {:skipped, :invalid_employee_id}
    else
      case Employees.get_open_entry(emp_id, business_id) do
        nil ->
          Logger.info(
            "Twilio SMS emp_clock_out skipped: sid=#{sid} reason=:no_open_entry employee_id=#{emp_id}"
          )

          {:skipped, :no_open_entry}

        entry ->
          case Employees.update_time_entry(entry, %{clocked_out_at: clocked_out_at}) do
            {:ok, updated} ->
              Logger.info(
                "Twilio SMS emp_clock_out applied: sid=#{sid} employee_id=#{emp_id} entry_id=#{updated.id}"
              )

              emp = Employees.get_employee(emp_id, business_id)
              {:emp_clocked_out, updated.id, emp && emp.name, updated.clocked_in_at, clocked_out_at}

            {:error, cs} ->
              Logger.warning("Twilio SMS emp_clock_out failed: #{inspect(cs.errors)}")
              {:error, :emp_clock_out_failed}
          end
      end
    end
  end

  defp apply_emp_operation(
         {:emp_lunch_by_id, emp_id, lunch_start, lunch_end},
         idx,
         sid,
         from,
         business_id,
         allowed_ids
       ) do
    Logger.info(
      "Twilio SMS emp lunch: sid=#{sid} from=#{from} op_index=#{idx} employee_id=#{emp_id}"
    )

    if not MapSet.member?(allowed_ids, emp_id) do
      Logger.info(
        "Twilio SMS emp_lunch skipped: sid=#{sid} reason=:invalid_employee_id employee_id=#{emp_id}"
      )

      {:skipped, :invalid_employee_id}
    else
      case Employees.get_open_entry(emp_id, business_id) do
        nil ->
          Logger.info(
            "Twilio SMS emp_lunch skipped: sid=#{sid} reason=:no_open_entry employee_id=#{emp_id}"
          )

          {:skipped, :no_open_entry}

        entry ->
          case Employees.update_time_entry(entry, %{
                 lunch_start_at: lunch_start,
                 lunch_end_at: lunch_end
               }) do
            {:ok, updated} ->
              Logger.info("Twilio SMS emp_lunch applied: sid=#{sid} employee_id=#{emp_id}")
              emp = Employees.get_employee(emp_id, business_id)
              {:emp_lunched, updated.id, emp && emp.name, lunch_start, lunch_end}

            {:error, cs} ->
              Logger.warning("Twilio SMS emp_lunch failed: #{inspect(cs.errors)}")
              {:error, :emp_lunch_failed}
          end
      end
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
            ok_ct = Enum.count(results, &match?({:ok, _}, &1))

            if ok_ct > 0 do
              Logger.info(
                "Twilio SMS attach_photos applied: sid=#{message_sid} op_index=#{idx} job_id=#{job.id} saved=#{ok_ct}/#{length(urls)}"
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

  defp twiml_ok(conn) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, empty_twiml())
  end

  defp empty_twiml do
    ~s(<?xml version="1.0" encoding="UTF-8"?><Response></Response>)
  end
end
