defmodule RompCrm.Twilio.Messages do
  @moduledoc """
  Outbound SMS via Twilio REST API (`POST .../Messages.json`).

  Requires **`TWILIO_ACCOUNT_SID`**, **`TWILIO_AUTH_TOKEN`**, and **`TWILIO_MESSAGING_FROM`**
  (E.164, e.g. `+18022780965`).
  """

  require Logger

  @messages_path "/2010-04-01/Accounts"

  @doc """
  Sends an SMS from the configured Twilio number to `to_e164`.

  Returns `{:ok, map}` with Twilio JSON body or `{:error, reason}`.
  """
  def send_sms(to_e164, body)
      when is_binary(to_e164) and is_binary(body) do
    unless sms_outbound_enabled?() do
      Logger.info("Twilio outbound skipped (disabled or incomplete config) to=#{to_e164}")
      {:ok, :skipped}
    else
      do_send(to_e164, body)
    end
  end

  defp sms_outbound_enabled? do
    Application.get_env(:romp_crm, :twilio_sms_replies_enabled, true) &&
      account_sid() not in [nil, ""] &&
      auth_token() not in [nil, ""] &&
      from_number() not in [nil, ""]
  end

  defp do_send(to_e164, body) do
    url = "https://api.twilio.com#{@messages_path}/#{account_sid()}/Messages.json"

    # SMS body max 1600 chars per Twilio; keep defensive trim
    safe_body = body |> String.trim() |> String.slice(0, 1600)

    case Req.post(url,
           auth: {:basic, "#{account_sid()}:#{auth_token()}"},
           form: [To: to_e164, From: from_number(), Body: safe_body],
           redirect: false,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: code} = resp} when code in 200..299 ->
        {:ok, resp.body}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning(
          "Twilio Messages API error status=#{status} to=#{to_e164} body=#{inspect(resp_body)}"
        )

        {:error, {:twilio_http, status, resp_body}}

      {:error, reason} ->
        Logger.warning("Twilio Messages request failed to=#{to_e164} reason=#{inspect(reason)}")
        {:error, {:request, reason}}
    end
  end

  defp account_sid, do: Application.get_env(:romp_crm, :twilio_account_sid)
  defp auth_token, do: Application.get_env(:romp_crm, :twilio_auth_token)

  defp from_number do
    Application.get_env(:romp_crm, :twilio_messaging_from_number) |> normalize_from()
  end

  defp normalize_from(nil), do: nil

  defp normalize_from(s) when is_binary(s) do
    s |> String.trim() |> then(fn x -> if x == "", do: nil, else: x end)
  end

  def account_sid_configured? do
    account_sid() not in [nil, ""]
  end
end
