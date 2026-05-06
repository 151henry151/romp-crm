defmodule JgsCrm.Twilio.PhoneTest do
  use ExUnit.Case, async: true

  alias JgsCrm.Twilio.Phone

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
end
