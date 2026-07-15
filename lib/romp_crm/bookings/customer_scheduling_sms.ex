defmodule RompCrm.Bookings.CustomerSchedulingSms do
  @moduledoc """
  Outbound SMS to **customers** for scheduling (booking invite, confirm/cancel,
  escalation relay, slot offers).

  Gated by **`ApplicationConfig.customer_scheduling_sms_enabled?/0`** (default off)
  so production can ship scheduling code without texting clients until ready.
  """

  require Logger

  alias RompCrm.ApplicationConfig
  alias RompCrm.Twilio.Messages

  def enabled?, do: ApplicationConfig.customer_scheduling_sms_enabled?()

  @doc """
  Sends to a customer E.164 number when the feature is enabled; otherwise logs and
  returns `{:ok, :feature_disabled}`.
  """
  def send_sms(to_e164, body) when is_binary(to_e164) and is_binary(body) do
    if enabled?() do
      Messages.send_sms(to_e164, body)
    else
      Logger.info("Customer scheduling SMS skipped (feature disabled) to=#{to_e164}")
      {:ok, :feature_disabled}
    end
  end
end
