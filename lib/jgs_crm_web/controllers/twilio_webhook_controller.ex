defmodule JgsCrmWeb.TwilioWebhookController do
  use JgsCrmWeb, :controller

  require Logger

  alias JgsCrm.Ai.SmsJobExtractor
  alias JgsCrm.Jobs
  alias JgsCrm.Twilio
  alias JgsCrm.Twilio.Signature

  @doc """
  Twilio `POST` webhook for inbound SMS. Configure the number's "A message comes in"
  URL to `https://YOUR_HOST/webhooks/twilio/sms` with HTTP POST.
  """
  def sms(conn, _params) do
    skip? = Application.get_env(:jgs_crm, :skip_twilio_signature_validation, false)
    token = Application.get_env(:jgs_crm, :twilio_auth_token)
    public_url = Application.get_env(:jgs_crm, :twilio_webhook_public_url)

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

    if Twilio.sms_sender_allowed?(from) do
      deliver_inbound_sms(conn)
    else
      message_sid = conn.body_params["MessageSid"] |> to_string()

      Logger.info(
        "Twilio SMS rejected: from not allowlisted sid=#{message_sid} from=#{inspect(from)}"
      )

      twiml_ok(conn)
    end
  end

  defp deliver_inbound_sms(conn) do
    body_text = (conn.body_params["Body"] || "") |> to_string()
    from = conn.body_params["From"] |> to_string()
    message_sid = conn.body_params["MessageSid"] |> to_string()

    Logger.info(
      "Twilio SMS inbound: sid=#{message_sid} from=#{from} body=#{inspect(body_text)}"
    )

    jobs_snapshot = Jobs.snapshot_for_sms_ai()
    allowed_job_ids = MapSet.new(Enum.map(jobs_snapshot, fn row -> row["id"] end))

    case SmsJobExtractor.extract(body_text, jobs_snapshot) do
      {:ok, operations} when is_list(operations) ->
        Logger.info(
          "Twilio SMS parsed operations: sid=#{message_sid} from=#{from} count=#{length(operations)}"
        )

        Enum.with_index(operations, 1)
        |> Enum.each(fn {op, idx} ->
          apply_sms_operation(op, idx, message_sid, from, allowed_job_ids)
        end)

        twiml_ok(conn)

      {:error, :missing_api_key} ->
        Logger.error(
          "Twilio SMS extraction failed: sid=#{message_sid} from=#{from} reason=:missing_api_key body=#{inspect(body_text)}"
        )

        twiml_ok(conn)

      {:error, reason} ->
        Logger.warning(
          "Twilio SMS extraction failed: sid=#{message_sid} from=#{from} reason=#{inspect(reason)} body=#{inspect(body_text)}"
        )

        twiml_ok(conn)
    end
  end

  defp apply_sms_operation({:create, attrs}, idx, message_sid, from, _allowed_job_ids) do
    Logger.info(
      "Twilio SMS parsed create: sid=#{message_sid} from=#{from} op_index=#{idx} attrs=#{inspect(attrs)}"
    )

    case Jobs.create_job(attrs) do
      {:ok, job} ->
        Logger.info(
          "Twilio SMS create applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id}"
        )

      {:error, changeset} ->
        Logger.warning(
          "Twilio SMS create failed: sid=#{message_sid} from=#{from} op_index=#{idx} errors=#{inspect(changeset.errors)}"
        )
    end
  end

  defp apply_sms_operation({:update_by_id, job_id, patch}, idx, message_sid, from, allowed_job_ids) do
    Logger.info(
      "Twilio SMS parsed update: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job_id} patch=#{inspect(patch)}"
    )

    cond do
      not MapSet.member?(allowed_job_ids, job_id) ->
        Logger.info(
          "Twilio SMS update skipped: sid=#{message_sid} from=#{from} op_index=#{idx} reason=:invalid_job_id job_id=#{job_id} patch=#{inspect(patch)}"
        )

      true ->
        case Jobs.get_job(job_id) do
          nil ->
            Logger.info(
              "Twilio SMS update skipped: sid=#{message_sid} from=#{from} op_index=#{idx} reason=:job_not_found job_id=#{job_id}"
            )

          job ->
            case Jobs.update_job(job, patch) do
              {:ok, updated_job} ->
                Logger.info(
                  "Twilio SMS update applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{updated_job.id} changed_fields=#{inspect(Map.keys(patch))}"
                )

              {:error, changeset} ->
                Logger.warning(
                  "Twilio SMS update failed: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id} errors=#{inspect(changeset.errors)}"
                )
            end
        end
    end
  end

  defp apply_sms_operation({:update, match, patch}, idx, message_sid, from, _allowed_job_ids) do
    Logger.info(
      "Twilio SMS parsed update: sid=#{message_sid} from=#{from} op_index=#{idx} match=#{inspect(match)} patch=#{inspect(patch)}"
    )

    case Jobs.find_job_for_sms_update(match) do
      {:ok, job} ->
        case Jobs.update_job(job, patch) do
          {:ok, updated_job} ->
            Logger.info(
              "Twilio SMS update applied: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{updated_job.id} changed_fields=#{inspect(Map.keys(patch))}"
            )

          {:error, changeset} ->
            Logger.warning(
              "Twilio SMS update failed: sid=#{message_sid} from=#{from} op_index=#{idx} job_id=#{job.id} errors=#{inspect(changeset.errors)}"
            )
        end

      {:error, reason} ->
        Logger.info(
          "Twilio SMS update skipped: sid=#{message_sid} from=#{from} op_index=#{idx} reason=#{inspect(reason)} match=#{inspect(match)} patch=#{inspect(patch)}"
        )
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
