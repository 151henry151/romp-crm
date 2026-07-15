defmodule RompCrm.ApplicationConfig do
  @moduledoc false

  @doc """
  Subscription paywall (PayPal) for the hosted product. Self-hosted installs keep this off.
  """
  def subscription_paywall_enabled? do
    Application.get_env(:romp_crm, :subscription_paywall_enabled, false) == true
  end

  @doc """
  When false (the default), the scheduling agent must not SMS customers — invitations,
  booking confirmations/cancellations, escalation relays, and slot offers are blocked.

  Enable with `CUSTOMER_SCHEDULING_SMS_ENABLED=true` (or Application config) when ready.
  """
  def customer_scheduling_sms_enabled? do
    Application.get_env(:romp_crm, :customer_scheduling_sms_enabled, false) == true
  end

  @doc false
  def signup_notify_emails do
    Application.get_env(:romp_crm, :signup_notify_emails, [])
  end
end
