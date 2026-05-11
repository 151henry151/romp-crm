defmodule RompCrm.Ai.SmsTimeExtractorTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsTimeExtractor

  describe "extract/3 with DeterministicStub" do
    test "STUB_TIME_IN returns clock_in_by_id operation" do
      raw =
        "STUB_TIME_IN " <>
          Jason.encode!(%{"job_id" => 42, "started_at" => "2026-05-11T08:00:00"})

      assert {:ok, %{assistant_sms: "Stub: clocked in.", operations: ops}} =
               SmsTimeExtractor.extract(raw, [])

      assert [{:clock_in_by_id, 42, ~N[2026-05-11 08:00:00]}] = ops
    end

    test "STUB_TIME_OUT returns clock_out_by_id operation" do
      raw =
        "STUB_TIME_OUT " <>
          Jason.encode!(%{"job_id" => 42, "ended_at" => "2026-05-11T14:00:00"})

      assert {:ok, %{operations: [{:clock_out_by_id, 42, ~N[2026-05-11 14:00:00]}]}} =
               SmsTimeExtractor.extract(raw, [])
    end

    test "non-time SMS returns empty operations" do
      assert {:ok, %{assistant_sms: nil, operations: []}} =
               SmsTimeExtractor.extract("Angela's address is 123 Main", [])
    end

    test "STUB_JSON message returns empty operations" do
      raw =
        "STUB_JSON " <> Jason.encode!(%{"intent" => "create", "job" => %{"client_name" => "X"}})

      assert {:ok, %{operations: []}} = SmsTimeExtractor.extract(raw, [])
    end

    test "STUB_EMP_IN message returns empty operations" do
      raw =
        "STUB_EMP_IN " <>
          Jason.encode!(%{"employee_id" => 1, "clocked_in_at" => "2026-05-11T08:00:00"})

      assert {:ok, %{operations: []}} = SmsTimeExtractor.extract(raw, [])
    end
  end

  describe "parse_naive_dt/1" do
    test "parses valid ISO 8601 datetime" do
      assert {:ok, ~N[2026-05-11 08:00:00]} =
               SmsTimeExtractor.parse_naive_dt("2026-05-11T08:00:00")
    end

    test "returns error for nil" do
      assert {:error, :missing_datetime} = SmsTimeExtractor.parse_naive_dt(nil)
    end

    test "returns error for empty string" do
      assert {:error, :missing_datetime} = SmsTimeExtractor.parse_naive_dt("")
    end

    test "returns error for invalid format" do
      assert {:error, {:invalid_datetime, "8am"}} = SmsTimeExtractor.parse_naive_dt("8am")
    end
  end

  describe "extract/3 with raw JSON payload" do
    test "returns clock_in_by_id with job_id in actions" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "assistant_sms" => "Clocked in.",
            "actions" => [
              %{"intent" => "clock_in", "job_id" => 5, "started_at" => "2026-05-11T08:00:00"}
            ]
          })

      assert {:ok, %{assistant_sms: "Clocked in.", operations: [{:clock_in_by_id, 5, _}]}} =
               SmsTimeExtractor.extract(raw, [])
    end

    test "returns clock_in with match when job_id absent" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "assistant_sms" => "Clocked in.",
            "actions" => [
              %{
                "intent" => "clock_in",
                "match" => %{"client_name" => "Angela"},
                "started_at" => "2026-05-11T08:00:00"
              }
            ]
          })

      assert {:ok,
              %{
                operations: [{:clock_in, %{"client_name" => "Angela"}, ~N[2026-05-11 08:00:00]}]
              }} = SmsTimeExtractor.extract(raw, [])
    end

    test "returns error for unknown intent" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{"intent" => "sleep", "job_id" => 1, "started_at" => "2026-05-11T08:00:00"}
            ]
          })

      assert {:error, {:invalid_action, 1, {:unknown_intent, "sleep"}}} =
               SmsTimeExtractor.extract(raw, [])
    end

    test "empty actions list returns empty operations" do
      raw = "STUB_JSON " <> Jason.encode!(%{"assistant_sms" => nil, "actions" => []})
      assert {:ok, %{operations: []}} = SmsTimeExtractor.extract(raw, [])
    end
  end
end
