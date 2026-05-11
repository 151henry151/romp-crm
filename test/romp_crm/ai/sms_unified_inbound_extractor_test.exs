defmodule RompCrm.Ai.SmsUnifiedInboundExtractorTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsUnifiedInboundExtractor

  describe "extract/4 with DeterministicStub" do
    test "STUB_TIME_IN yields time_operations only" do
      raw =
        "STUB_TIME_IN " <>
          Jason.encode!(%{"job_id" => 9, "started_at" => "2026-05-11T08:00:00"})

      assert {:ok,
              %{
                assistant_sms: "Stub: clocked in.",
                job_operations: [],
                time_operations: [{:clock_in_by_id, 9, ~N[2026-05-11 08:00:00]}],
                emp_operations: []
              }} =
               SmsUnifiedInboundExtractor.extract(raw, [], [], [])
    end

    test "STUB_UPDATE with job_id yields job_operations only" do
      raw =
        "STUB_UPDATE " <>
          Jason.encode!(%{
            "job_id" => 3,
            "updates" => %{"address" => "1 Main"}
          })

      assert {:ok,
              %{
                job_operations: [{:update_by_id, 3, patch}],
                time_operations: [],
                emp_operations: []
              }} =
               SmsUnifiedInboundExtractor.extract(raw, [], [], [])

      assert patch[:address] == "1 Main"
    end
  end
end
