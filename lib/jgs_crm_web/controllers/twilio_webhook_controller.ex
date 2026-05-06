defmodule JgsCrmWeb.TwilioWebhookController do
  use JgsCrmWeb, :controller

  require Logger

  alias JgsCrm.Ai.SmsJobExtractor
  alias JgsCrm.Jobs
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
        deliver_inbound_sms(conn)
    end
  end

  defp deliver_inbound_sms(conn) do
    body_text = (conn.body_params["Body"] || "") |> to_string()

    case SmsJobExtractor.extract(body_text) do
      {:ok, {:create, attrs}} ->
        case Jobs.create_job(attrs) do
          {:ok, _job} ->
            twiml_ok(conn)

          {:error, changeset} ->
            Logger.warning("Twilio SMS job insert failed: #{inspect(changeset.errors)}")
            twiml_ok(conn)
        end

      {:ok, {:update, match, patch}} ->
        case Jobs.find_job_for_sms_update(match) do
          {:ok, job} ->
            case Jobs.update_job(job, patch) do
              {:ok, _job} ->
                twiml_ok(conn)

              {:error, changeset} ->
                Logger.warning("Twilio SMS job update failed: #{inspect(changeset.errors)}")
                twiml_ok(conn)
            end

          {:error, reason} ->
            Logger.info("Twilio SMS update skipped (match): #{inspect(reason)}, match=#{inspect(match)}")
            twiml_ok(conn)
        end

      {:error, :missing_api_key} ->
        Logger.error("ANTHROPIC_API_KEY is not set; cannot parse SMS")
        twiml_ok(conn)

      {:error, reason} ->
        Logger.warning("SMS job extraction failed: #{inspect(reason)}")
        twiml_ok(conn)
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
