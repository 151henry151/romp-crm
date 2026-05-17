defmodule RompCrm.Ai.SmsEmployeeTimeExtractorTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsEmployeeTimeExtractor

  describe "extract/2 with DeterministicStub" do
    test "STUB_EMP_IN returns emp_clock_in_by_id operation" do
      raw =
        "STUB_EMP_IN " <>
          Jason.encode!(%{"employee_id" => 1, "clocked_in_at" => "2026-05-11T08:00:00"})

      assert {:ok, %{assistant_sms: "Stub: employee clocked in.", operations: ops}} =
               SmsEmployeeTimeExtractor.extract(raw, [])

      assert [{:emp_clock_in_by_id, 1, ~N[2026-05-11 08:00:00]}] = ops
    end

    test "STUB_EMP_OUT returns emp_clock_out_by_id operation" do
      raw =
        "STUB_EMP_OUT " <>
          Jason.encode!(%{"employee_id" => 1, "clocked_out_at" => "2026-05-11T16:00:00"})

      assert {:ok, %{operations: [{:emp_clock_out_by_id, 1, ~N[2026-05-11 16:00:00]}]}} =
               SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "STUB_EMP_LUNCH returns emp_lunch_by_id operation" do
      raw =
        "STUB_EMP_LUNCH " <>
          Jason.encode!(%{
            "employee_id" => 1,
            "lunch_start_at" => "2026-05-11T12:00:00",
            "lunch_end_at" => "2026-05-11T13:00:00"
          })

      assert {:ok,
              %{
                operations: [
                  {:emp_lunch_by_id, 1, ~N[2026-05-11 12:00:00], ~N[2026-05-11 13:00:00]}
                ]
              }} =
               SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "non-employee SMS returns empty operations" do
      assert {:ok, %{assistant_sms: nil, operations: []}} =
               SmsEmployeeTimeExtractor.extract("Angela's address is 123 Main", [])
    end

    test "STUB_TIME_IN returns empty operations (not employee domain)" do
      raw =
        "STUB_TIME_IN " <> Jason.encode!(%{"job_id" => 1, "started_at" => "2026-05-11T08:00:00"})

      assert {:ok, %{operations: []}} = SmsEmployeeTimeExtractor.extract(raw, [])
    end
  end

  describe "extract/2 with raw JSON payload" do
    test "returns emp_clock_in_by_id from actions" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "assistant_sms" => "Henry clocked in.",
            "actions" => [
              %{
                "intent" => "clock_in",
                "employee_id" => 3,
                "clocked_in_at" => "2026-05-11T08:00:00"
              }
            ]
          })

      assert {:ok, %{operations: [{:emp_clock_in_by_id, 3, ~N[2026-05-11 08:00:00]}]}} =
               SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "returns error when clock_in has match but no employee_id" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "clock_in",
                "match" => %{"name" => "Henry"},
                "clocked_in_at" => "2026-05-11T08:00:00"
              }
            ]
          })

      assert {:error, {:invalid_action, 1, :missing_employee_id}} =
               SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "returns emp_lunch_by_id from actions" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "lunch",
                "employee_id" => 2,
                "lunch_start_at" => "2026-05-11T12:00:00",
                "lunch_end_at" => "2026-05-11T13:00:00"
              }
            ]
          })

      assert {:ok,
              %{
                operations: [
                  {:emp_lunch_by_id, 2, ~N[2026-05-11 12:00:00], ~N[2026-05-11 13:00:00]}
                ]
              }} = SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "multiple operations returned in order" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "clock_in",
                "employee_id" => 1,
                "clocked_in_at" => "2026-05-11T08:00:00"
              },
              %{
                "intent" => "clock_in",
                "employee_id" => 2,
                "clocked_in_at" => "2026-05-11T08:30:00"
              }
            ]
          })

      assert {:ok, %{operations: [op1, op2]}} = SmsEmployeeTimeExtractor.extract(raw, [])
      assert {:emp_clock_in_by_id, 1, _} = op1
      assert {:emp_clock_in_by_id, 2, _} = op2
    end

    test "returns error for unknown intent" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "teleport",
                "employee_id" => 1,
                "clocked_in_at" => "2026-05-11T08:00:00"
              }
            ]
          })

      assert {:error, {:invalid_action, 1, {:unknown_intent, "teleport"}}} =
               SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "log_shift returns emp_log_shift_by_id" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "log_shift",
                "employee_id" => 2,
                "clocked_in_at" => "2026-05-11T08:00:00",
                "clocked_out_at" => "2026-05-11T16:00:00"
              }
            ]
          })

      assert {:ok,
              %{
                operations: [
                  {:emp_log_shift_by_id, 2, ~N[2026-05-11 08:00:00], ~N[2026-05-11 16:00:00], nil, nil}
                ]
              }} = SmsEmployeeTimeExtractor.extract(raw, [])
    end

    test "empty actions returns empty operations" do
      raw = "STUB_JSON " <> Jason.encode!(%{"assistant_sms" => nil, "actions" => []})
      assert {:ok, %{operations: []}} = SmsEmployeeTimeExtractor.extract(raw, [])
    end
  end

  describe "parse_naive_dt/1" do
    test "parses valid ISO 8601" do
      assert {:ok, ~N[2026-05-11 16:00:00]} =
               SmsEmployeeTimeExtractor.parse_naive_dt("2026-05-11T16:00:00")
    end

    test "returns error for nil" do
      assert {:error, :missing_datetime} = SmsEmployeeTimeExtractor.parse_naive_dt(nil)
    end
  end
end
