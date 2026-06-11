defmodule RompCrm.Scheduling.TimezoneInferenceTest do
  use ExUnit.Case, async: true

  alias RompCrm.Scheduling.TimezoneInference

  test "from_phone/1 maps Vermont area code to Eastern" do
    assert TimezoneInference.from_phone("18027349389") == "America/New_York"
  end

  test "from_phone/1 maps Chicago area code" do
    assert TimezoneInference.from_phone("13125550123") == "America/Chicago"
  end

  test "from_phone/1 defaults for blank" do
    assert TimezoneInference.from_phone(nil) == "America/New_York"
    assert TimezoneInference.from_phone("") == "America/New_York"
  end
end
