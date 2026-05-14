defmodule RompCrm.SmsAssistantIntro do
  @moduledoc false

  alias RompCrm.Accounts.User
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @welcome_body """
                Hi! I'm your Romp CRM assistant. You can text me things like "Sally wants her kitchen faucet replaced next wednesday" or "Remind me to buy a toilet supply line for Kevin tomorrow morning" and I'll update the relevant job in your job list for you, or make a new one. Try it out! I can also look up information for you, like "how many hours has Dave worked so far at the job where we're installing a new boiler in Monkton?", or I can add time logs to jobs, try "We worked at John's place for 4 hours today, 2pm to 6pm, it was me and Sam" -- just text me whatever you would text your assistant and I'll do my best! I always text back and let you know what I understood and what I'm doing.
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
