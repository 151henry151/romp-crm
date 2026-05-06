defmodule JgsCrm.Ai.SmsJobExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double: returns predictable JSON-shaped maps without calling Anthropic.
  """
  def extract(raw_message) when is_binary(raw_message) do
    {:ok,
     %{
       "client_name" => "Test SMS Lead",
       "address" => nil,
       "phone" => nil,
       "work_description" => String.slice(raw_message, 0, 500),
       "priority" => "normal",
       "status" => "lead",
       "referred_by" => nil,
       "notes" => nil,
       "next_action" => nil
     }}
  end
end
