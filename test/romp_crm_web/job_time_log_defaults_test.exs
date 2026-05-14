defmodule RompCrmWeb.JobTimeLogDefaultsTest do
  use ExUnit.Case, async: true

  alias RompCrmWeb.JobTimeLogDefaults

  test "to_datetime_local formats naive datetime for datetime-local inputs" do
    assert JobTimeLogDefaults.to_datetime_local(~N[2026-05-11 14:07:00]) == "2026-05-11T14:07"
  end
end
