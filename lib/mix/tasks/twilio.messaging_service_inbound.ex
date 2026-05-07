defmodule Mix.Tasks.Twilio.MessagingServiceInbound do
  @moduledoc """
  Sets **UseInboundWebhookOnNumber=true** on a Twilio **Messaging Service**.

  When your CRM number (e.g. **+18022780965**) is attached to a Messaging Service for A2P/outbound,
  Twilio otherwise ignores the number's **SmsUrl** for inbound unless this flag is enabled or you set
  **Inbound Request URL** on the service.

  Requires **`TWILIO_ACCOUNT_SID`**, **`TWILIO_AUTH_TOKEN`**, and **`TWILIO_MESSAGING_SERVICE_SID`**
  (find it under Twilio Console → Messaging → Services, or list via API).

  ## Example

      TWILIO_MESSAGING_SERVICE_SID=MGxxxxxxxx \\
        mix twilio.messaging_service_inbound

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    account_sid = System.get_env("TWILIO_ACCOUNT_SID") |> to_string() |> String.trim()
    auth_token = System.get_env("TWILIO_AUTH_TOKEN") |> to_string() |> String.trim()
    service_sid = System.get_env("TWILIO_MESSAGING_SERVICE_SID") |> to_string() |> String.trim()

    if account_sid == "" or auth_token == "" do
      Mix.raise("Set TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN")
    end

    if service_sid == "" do
      Mix.raise(
        "Set TWILIO_MESSAGING_SERVICE_SID to your Messaging Service SID (Console → Messaging → Services)."
      )
    end

    url = "https://messaging.twilio.com/v1/Services/#{service_sid}"

    case Req.post(url,
           auth: {:basic, "#{account_sid}:#{auth_token}"},
           form: [UseInboundWebhookOnNumber: "true"],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: code} = resp} when code in 200..299 ->
        body = resp.body

        flag =
          cond do
            is_map(body) && Map.has_key?(body, "use_inbound_webhook_on_number") ->
              Map.get(body, "use_inbound_webhook_on_number")

            is_map(body) && Map.has_key?(body, :use_inbound_webhook_on_number) ->
              Map.get(body, :use_inbound_webhook_on_number)

            true ->
              inspect(body)
          end

        Mix.shell().info(
          "Messaging Service #{service_sid}: use_inbound_webhook_on_number=#{inspect(flag)}"
        )

      {:ok, %{status: status, body: body}} ->
        Mix.raise("Twilio update failed status=#{status} body=#{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Twilio request failed: #{inspect(reason)}")
    end
  end
end
