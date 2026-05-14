defmodule RompCrmWeb.JobExpandEditKeysTest do
  use ExUnit.Case, async: true

  alias RompCrmWeb.JobExpandEditKeys, as: K

  test "job/2 and row edit keys are stable strings" do
    assert K.job(9, "client_name") == "job:9:client_name"
    assert K.wi_edit(12) == "wi:12:edit"
    assert K.mat_edit(3) == "mat:3:edit"
  end
end
