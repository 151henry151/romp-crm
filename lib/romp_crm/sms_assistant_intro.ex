defmodule RompCrm.SmsAssistantIntro do
  @moduledoc false

  alias RompCrm.Accounts.User
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @welcome_body """
  Romp CRM assistant: text me in plain language about jobs—new work, changes, reminders, time worked, quick questions. I'll text back what I understood and did.
  """
  |> String.trim()

  @doc "Outbound welcome SMS after the user saves a phone number from the first-login intro."
  def welcome_sms_body, do: @welcome_body

  @doc """
  Sends **`welcome_sms_body/0`** to **`user`** when **`phone_normalized`** is set.

  Returns **`{:ok, :skipped}`** when Twilio outbound is disabled or **`{:ok, resp}`** / **`{:error, reason}`** from **`Messages.send_sms/2`**.
  """
  def send_welcome_sms(%User{} = user) do
    case Phone.to_e164(user.phone_normalized) do
      nil ->
        {:ok, :no_e164}

      to ->
        Messages.send_sms(to, welcome_sms_body())
    end
  end
end
