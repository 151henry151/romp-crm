defmodule RompCrm.Ai.SmsUnifiedInboundExtractor do
  @moduledoc """
  Single-call extraction for inbound contractor SMS: jobs, job time tracking, and employee time.

  One Anthropic request receives **jobs**, **open job time entries**, and **employees** snapshots so the model
  can align the SMS with live rows (same judgment-based matching as job updates — **no** server-side fuzzy name scripts).

  Configure **`sms_unified_inbound_adapter`** (tests use **`DeterministicStub`**).
  """

  alias RompCrm.Ai.SmsEmployeeTimeExtractor
  alias RompCrm.Ai.SmsJobExtractor
  alias RompCrm.Ai.SmsTimeExtractor

  @doc """
  Returns:

    * **`{:ok, %{assistant_sms, job_operations, time_operations, emp_operations}}`**
    * **`{:error, reason}`**

  """
  def extract(raw_message, jobs_snapshot, open_time_entries_snapshot, employees_snapshot)
      when is_binary(raw_message) and is_list(jobs_snapshot) and is_list(open_time_entries_snapshot) and
             is_list(employees_snapshot) do
    mod =
      Application.get_env(
        :romp_crm,
        :sms_unified_inbound_adapter,
        __MODULE__.Anthropic
      )

    case mod.extract(raw_message, jobs_snapshot, open_time_entries_snapshot, employees_snapshot) do
      {:ok, %{} = attrs} -> parse_combined_payload(attrs)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_combined_payload(map) when is_map(map) do
    map = stringify_keys(map)

    assistant =
      case Map.get(map, "assistant_sms") do
        s when is_binary(s) -> s |> String.trim() |> String.slice(0, 480)
        _ -> nil
      end

    job_actions = Map.get(map, "job_actions")
    time_actions = Map.get(map, "time_actions")
    employee_actions = Map.get(map, "employee_actions")

    job_actions = if is_list(job_actions), do: job_actions, else: []
    time_actions = if is_list(time_actions), do: time_actions, else: []
    employee_actions = if is_list(employee_actions), do: employee_actions, else: []

    with {:ok, job_ops} <- SmsJobExtractor.parse_actions_list(job_actions),
         {:ok, time_ops} <- SmsTimeExtractor.parse_actions_list(time_actions),
         {:ok, emp_ops} <- SmsEmployeeTimeExtractor.parse_actions_list(employee_actions) do
      {:ok,
       %{
         assistant_sms: assistant,
         job_operations: job_ops,
         time_operations: time_ops,
         emp_operations: emp_ops
       }}
    end
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
