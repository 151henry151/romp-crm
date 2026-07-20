defmodule RompCrm.Ai.SmsUnifiedInboundExtractor.AnthropicParseTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsUnifiedInboundExtractor.Anthropic

  test "decode_model_text accepts bare JSON object" do
    assert {:ok, %{"time_actions" => [_ | _]}} =
             Anthropic.decode_model_text(~s({"assistant_sms":"ok","time_actions":[{"intent":"clock_out","job_id":1,"ended_at":"2026-07-20T12:13:00"}]}))
  end

  test "decode_model_text strips markdown fences" do
    text = """
    ```json
    {"assistant_sms":"Clocked out.","job_actions":[],"time_actions":[]}
    ```
    """

    assert {:ok, %{"assistant_sms" => "Clocked out."}} = Anthropic.decode_model_text(text)
  end

  test "decode_model_text returns invalid_json_from_model for prose" do
    assert {:error, :invalid_json_from_model} =
             Anthropic.decode_model_text("Sure, I'll clock you out of that job now.")
  end
end
