defmodule RompCrmWeb.TwilioWebhookController do
  use RompCrmWeb, :controller

  require Logger

  alias RompCrm.Accounts
  alias RompCrm.Ai.SmsJobExtractor
  alias RompCrm.Businesses
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
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

    case SmsJobExtractor.extract(body_text, jobs_snapshot) do
      {:ok, %{assistant_sms: assistant, operations: ops}} when ops == [] ->
        if is_binary(assistant) and String.trim(assistant) != "" do
          _ = Messages.send_sms(from, String.trim(assistant))
        end

        twiml_ok(conn)

      {:ok, %{assistant_sms: assistant, operations: ops}} ->
        Logger.info(
          "Twilio SMS parsed operations: sid=#{message_sid} count=#{length(ops)} from=#{from}"
        )

        case run_operations(ops, message_sid, from, business_id, allowed_job_ids) do
          {:clarify, msg} ->
            _ = Messages.send_sms(from, msg)
            twiml_ok(conn)

          {:ok, results} ->
            reply = SmsReplyBuilder.compose(assistant, results)
            _ = Messages.send_sms(from, reply)
            twiml_ok(conn)
        end

      {:error, :missing_api_key} ->
        Logger.error(
          "Twilio SMS extraction failed: sid=#{message_sid} from=#{from} reason=:missing_api_key body=#{inspect(body_text)}"
        )

        twiml_ok(conn)

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS extraction failed: sid=#{message_sid} from=#{from} reason=#{inspect(reason)} body=#{inspect(body_text)}"
        )

        _ =
          Messages.send_sms(
            from,
            parse_error_user_message(reason)
          )

        twiml_ok(conn)
    end
  end

  defp parse_error_user_message(:empty_extract),
    do: "Not sure what to change—name the client or paste more detail."

  defp parse_error_user_message(_),
    do: "Couldn't parse that—try naming the client or job."

  defp run_operations(ops, message_sid, from, business_id, allowed_job_ids) do
    Enum.reduce_while(Enum.with_index(ops, 1), [], fn {op, idx}, acc ->
      case apply_sms_operation_ret(op, idx, message_sid, from, business_id, allowed_job_ids) do
        {:clarify_match, msg} ->
          {:halt, {:clarify, msg}}

        other ->
          {:cont, [other | acc]}
      end
    end)
    |> case do
      {:clarify, msg} ->
        {:clarify, msg}

      rev when is_list(rev) ->
        {:ok, Enum.reverse(rev)}
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

  defp twiml_ok(conn) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, empty_twiml())
  end

  defp empty_twiml do
    ~s(<?xml version="1.0" encoding="UTF-8"?><Response></Response>)
  end
end
