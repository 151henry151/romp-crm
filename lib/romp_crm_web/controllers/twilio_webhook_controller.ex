defmodule RompCrmWeb.TwilioWebhookController do
  use RompCrmWeb, :controller

  require Logger

  alias RompCrm.Accounts
  alias RompCrm.Ai.SmsUnifiedInboundExtractor
  alias RompCrm.Businesses
  alias RompCrm.Employees
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
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

  defp deliver_inbound_sms(conn, user, business_id) do
    body_text = (conn.body_params["Body"] || "") |> to_string()
    from = conn.body_params["From"] |> to_string()
    to_num = conn.body_params["To"] |> to_string()
    message_sid = conn.body_params["MessageSid"] |> to_string()

    Logger.info(
      "Twilio SMS inbound: sid=#{message_sid} to=#{inspect(to_num)} user_id=#{user.id} business_id=#{business_id} from=#{from} body=#{inspect(body_text)}"
    )

    jobs_snapshot = Jobs.snapshot_for_sms_ai(business_id)
    allowed_job_ids = MapSet.new(Enum.map(jobs_snapshot, fn row -> row["id"] end))

    open_time_entries = TimeTracking.snapshot_for_sms_ai(business_id)
    employees_snapshot = Employees.snapshot_for_sms_ai(business_id)
    allowed_employee_ids = MapSet.new(Enum.map(employees_snapshot, fn row -> row["id"] end))

    case SmsUnifiedInboundExtractor.extract(
           body_text,
           jobs_snapshot,
           open_time_entries,
           employees_snapshot
         ) do
      {:ok,
       %{
         assistant_sms: assistant,
         job_operations: job_ops,
         time_operations: time_ops,
         emp_operations: emp_ops
       }} ->
        all_ops = job_ops ++ time_ops ++ emp_ops

        cond do
          all_ops == [] ->
            msg = first_nonempty([assistant])

            reply =
              msg ||
                "No changes applied. Open Romp CRM or include clearer job/time details."

            _ = Messages.send_sms(from, reply)
            twiml_ok(conn)

          true ->
            Logger.info(
              "Twilio SMS parsed operations: sid=#{message_sid} count=#{length(all_ops)} from=#{from}"
            )

            job_ctx = %{
              message_sid: message_sid,
              from: from,
              business_id: business_id,
              allowed_job_ids: allowed_job_ids
            }

            case run_all_operations(job_ops, time_ops, emp_ops, job_ctx, allowed_employee_ids) do
              {:clarify, msg} ->
                _ = Messages.send_sms(from, msg)
                twiml_ok(conn)

              {:ok, all_results} ->
                combined_assistant = first_nonempty([assistant])
                reply = SmsReplyBuilder.compose(combined_assistant, all_results)
                _ = Messages.send_sms(from, reply)
                twiml_ok(conn)
            end
        end

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS unified extraction failed: sid=#{message_sid} from=#{from} reason=#{inspect(reason)}"
        )

        _ = Messages.send_sms(from, sms_extraction_failed_reply(reason))
        twiml_ok(conn)
    end
  end

  # Runs all operation lists and collects results. Job fuzzy-match errors trigger clarification.
  defp run_all_operations(job_ops, time_ops, emp_ops, job_ctx, allowed_employee_ids) do
    with {:ok, job_results} <- run_job_operations(job_ops, job_ctx),
         {:ok, time_results} <- run_time_operations(time_ops, job_ctx),
         {:ok, emp_results} <-
           run_emp_operations(
             emp_ops,
             job_ctx.message_sid,
             job_ctx.from,
             job_ctx.business_id,
             allowed_employee_ids
           ) do
      {:ok, job_results ++ time_results ++ emp_results}
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

              {:time_clocked_in, job.client_name, started_at}

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
              {:time_clocked_out, job && job.client_name, updated.started_at, ended_at}

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

              {:emp_clocked_in, emp.name, clocked_in_at}

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
              {:emp_clocked_out, emp && emp.name, updated.clocked_in_at, clocked_out_at}

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
            {:ok, _updated} ->
              Logger.info("Twilio SMS emp_lunch applied: sid=#{sid} employee_id=#{emp_id}")
              emp = Employees.get_employee(emp_id, business_id)
              {:emp_lunched, emp && emp.name, lunch_start, lunch_end}

            {:error, cs} ->
              Logger.warning("Twilio SMS emp_lunch failed: #{inspect(cs.errors)}")
              {:error, :emp_lunch_failed}
          end
      end
    end
  end

  # ── Existing job operation (kept as-is) ──────────────────────────────────

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
        Logger.info(
          "Twilio SMS create applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id}"
        )

        {:created, job}

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

            case Jobs.update_job(job, patch) do
              {:ok, %Job{} = updated_job} ->
                Logger.info(
                  "Twilio SMS update applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{updated_job.id} changed_fields=#{inspect(Map.keys(patch))}"
                )

                {:updated, updated_job, Map.keys(patch)}

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
        case Jobs.update_job(job, patch) do
          {:ok, %Job{} = updated_job} ->
            Logger.info(
              "Twilio SMS update applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{updated_job.id} changed_fields=#{inspect(Map.keys(patch))}"
            )

            {:updated, updated_job, Map.keys(patch)}

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
