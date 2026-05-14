defmodule Mix.Tasks.Twilio.ConfigureVoice do
  @moduledoc """
  Points a Twilio phone number’s **voice webhook** at your Romp CRM `/webhooks/twilio/voice` URL via the REST API.

  Does **not** change the **SMS** webhook (`SmsUrl`).

  Requires **`TWILIO_ACCOUNT_SID`** and **`TWILIO_AUTH_TOKEN`**.

  ## Examples

      TWILIO_VOICE_WEBHOOK_PUBLIC_URL="https://hromp.com/romp-crm/webhooks/twilio/voice" \\
        mix twilio.configure_voice

      mix twilio.configure_voice --phone +18022780965 \\
        --voice-url https://hromp.com/romp-crm/webhooks/twilio/voice

  `TWILIO_VOICE_WEBHOOK_PUBLIC_URL` must match the URL used for Twilio request signing
  (`:twilio_voice_webhook_public_url` / `Signature.valid?/3`).
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, _} =
      OptionParser.parse!(args,
        strict: [phone: :string, voice_url: :string],
        aliases: [p: :phone, v: :voice_url]
      )

    account_sid = System.get_env("TWILIO_ACCOUNT_SID") |> to_string() |> String.trim()
    auth_token = System.get_env("TWILIO_AUTH_TOKEN") |> to_string() |> String.trim()

    phone =
      (opts[:phone] || System.get_env("TWILIO_CONFIGURE_PHONE") || "+18022780965")
      |> to_string()
      |> String.trim()

    voice_url =
      (opts[:voice_url] || System.get_env("TWILIO_VOICE_WEBHOOK_PUBLIC_URL"))
      |> case do
        nil -> ""
        s -> to_string(s) |> String.trim()
      end

    if account_sid == "" or auth_token == "" do
      Mix.raise(
        "Set TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN (use the same credentials as the CRM release)."
      )
    end

    if voice_url == "" do
      Mix.raise(
        "Set TWILIO_VOICE_WEBHOOK_PUBLIC_URL or pass --voice-url to the full HTTPS webhook, " <>
          "e.g. https://hromp.com/romp-crm/webhooks/twilio/voice"
      )
    end

    unless String.starts_with?(voice_url, "https://") do
      Mix.raise(
        "--voice-url / TWILIO_VOICE_WEBHOOK_PUBLIC_URL must use https:// for production webhooks"
      )
    end

    {:ok, pn_sid} = fetch_incoming_phone_sid(account_sid, auth_token, phone)
    :ok = update_voice_webhook(account_sid, auth_token, pn_sid, voice_url)

    Mix.shell().info(
      "Twilio Voice webhook updated: phone=#{phone} sid=#{pn_sid} VoiceUrl=#{voice_url} VoiceMethod=POST (SmsUrl unchanged)"
    )
  end

  defp fetch_incoming_phone_sid(account_sid, auth_token, phone_e164) do
    q = URI.encode_query(%{"PhoneNumber" => phone_e164})

    url =
      "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/IncomingPhoneNumbers.json?#{q}"

    case Req.get(url,
           auth: {:basic, "#{account_sid}:#{auth_token}"},
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        numbers =
          cond do
            is_map(body) and match?(%{"incoming_phone_numbers" => _}, body) ->
              Map.fetch!(body, "incoming_phone_numbers")

            is_map(body) and match?(%{incoming_phone_numbers: _}, body) ->
              Map.fetch!(body, :incoming_phone_numbers)

            true ->
              []
          end

        case numbers do
          [%{"sid" => sid} | _] ->
            {:ok, sid}

          [%{sid: sid} | _] ->
            {:ok, sid}

          [] ->
            Mix.raise(
              "No IncomingPhoneNumber found for #{phone_e164}. Buy or import the number in Twilio first."
            )

          _ ->
            Mix.raise(
              "Unexpected Twilio IncomingPhoneNumbers payload for #{phone_e164}: #{inspect(body)}"
            )
        end

      {:ok, %{status: code, body: body}} ->
        Mix.raise("Twilio list IncomingPhoneNumbers failed status=#{code} body=#{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Twilio list IncomingPhoneNumbers request failed: #{inspect(reason)}")
    end
  end

  defp update_voice_webhook(account_sid, auth_token, pn_sid, voice_url) do
    url =
      "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/IncomingPhoneNumbers/#{pn_sid}.json"

    form = [VoiceUrl: voice_url, VoiceMethod: "POST"]

    case Req.post(url,
           auth: {:basic, "#{account_sid}:#{auth_token}"},
           form: form,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: code}} when code in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Mix.raise(
          "Twilio update phone number (voice) failed status=#{status} body=#{inspect(body)}"
        )

      {:error, reason} ->
        Mix.raise("Twilio update phone number request failed: #{inspect(reason)}")
    end
  end
end
