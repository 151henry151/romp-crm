defmodule RompCrm.SchedulingAgentTest.ErrorReplyTest do
  use ExUnit.Case, async: true

  alias RompCrm.SchedulingAgentTest.ErrorReply

  test "anthropic 529 overloaded" do
    msg = ErrorReply.for_reason({:anthropic_http, 529, %{"error" => %{"type" => "overloaded_error"}}})
    assert msg =~ "busy"
    refute msg =~ "anthropic_http"
  end

  test "generic failure hides internal tuple" do
    msg = ErrorReply.for_reason({:something, :weird})
    refute msg =~ "inspect"
    refute msg =~ "something"
  end
end
