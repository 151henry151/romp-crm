defmodule RompCrmWeb.JobExpandEditKeysTest do
  use ExUnit.Case, async: true

  alias RompCrmWeb.JobExpandEditKeys, as: K

  test "job/2 and wi_* / mat_* keys are stable strings" do
    assert K.job(9, "client_name") == "job:9:client_name"
    assert K.wi_title(12) == "wi:12:title"
    assert K.wi_scheduled(12) == "wi:12:scheduled_on"
    assert K.mat_quantity(3) == "mat:3:quantity"
    assert K.mat_description(3) == "mat:3:description"
  end
end
