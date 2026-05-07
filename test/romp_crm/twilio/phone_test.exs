defmodule RompCrm.Twilio.PhoneTest do
  use ExUnit.Case, async: true

  alias RompCrm.Twilio.Phone

  describe "normalize_us/1" do
    test "normalizes Twilio E.164 and formatted variants to the same key" do
      expected = "18024587299"

      assert Phone.normalize_us("+18024587299") == expected
      assert Phone.normalize_us("+1 (802) 458-7299") == expected
      assert Phone.normalize_us("(802) 458-7299") == expected
      assert Phone.normalize_us("802-458-7299") == expected
    end

    test "normalizes second allowlisted number" do
      assert Phone.normalize_us("+18024582710") == "18024582710"
      assert Phone.normalize_us("+1(802)458-2710") == "18024582710"
    end
  end

  describe "format_us_display/1" do
    test "formats E.164 intake line for dashboard copy" do
      assert Phone.format_us_display("+18022780965") == "(802) 278-0965"
    end
  end

  describe "sms_uri/1" do
    test "builds sms: href target from configured From number" do
      assert Phone.sms_uri("+18022780965") == "sms:+18022780965"
    end
  end
end
