defmodule RompCrm.Twilio.MessagesTest do
  use ExUnit.Case, async: true

  alias RompCrm.Twilio.Messages

  setup do
    prev = Application.get_env(:romp_crm, :twilio_sms_replies_enabled)

    on_exit(fn ->
      if is_nil(prev) do
        Application.delete_env(:romp_crm, :twilio_sms_replies_enabled)
      else
        Application.put_env(:romp_crm, :twilio_sms_replies_enabled, prev)
      end
    end)

    :ok
  end

  test "send_mms/3 skips when outbound is disabled" do
    Application.put_env(:romp_crm, :twilio_sms_replies_enabled, false)

    assert {:ok, :skipped} =
             Messages.send_mms("+18025550100", "caption", [
               "https://example.com/romp-crm/uploads/chat-media/1/a.jpg"
             ])
  end

  test "send_mms/3 rejects empty body with no media" do
    Application.put_env(:romp_crm, :twilio_sms_replies_enabled, false)

    assert {:error, :empty} = Messages.send_mms("+18025550100", "  ", [])
  end
end
