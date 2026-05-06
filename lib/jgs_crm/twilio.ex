defmodule JgsCrm.Twilio do
  @moduledoc false

  alias JgsCrm.Twilio.Phone

  @doc """
  Returns true if `from` is allowed to drive CRM updates via the inbound SMS webhook.

  Expects `Application.get_env(:jgs_crm, :twilio_sms_allowed_from_normalized)` to be a list of
  strings from `Phone.normalize_us/1`. Empty allowlist rejects all senders (fail closed).
  """
  def sms_sender_allowed?(from) when is_binary(from) do
    allowed = Application.get_env(:jgs_crm, :twilio_sms_allowed_from_normalized, [])
    norm = Phone.normalize_us(from)
    norm != "" and norm in allowed
  end

  def sms_sender_allowed?(_), do: false
end
