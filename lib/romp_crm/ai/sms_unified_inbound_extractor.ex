defmodule RompCrm.Ai.SmsUnifiedInboundExtractor do
  @moduledoc """
  Single-call extraction for inbound contractor SMS: jobs, job time tracking, employee time, and optional reminder scheduling.

  One Anthropic request receives **jobs**, **open job time entries**, and **employees** snapshots so the model
  can align the SMS with live rows (same judgment-based matching as job updates — **no** server-side fuzzy name scripts).

  Optionally receives **`prior_turns`** — **`[{role, text}]`** with **`role`** **`:contractor`** or **`:assistant`**,
  oldest first — so follow-up SMS can reference the ongoing thread.

  Configure **`sms_unified_inbound_adapter`** (tests use **`DeterministicStub`**).
  """

  alias RompCrm.Ai.SmsEmployeeTimeExtractor
  alias RompCrm.Ai.SmsJobExtractor
  alias RompCrm.Ai.SmsReminderExtractor
  alias RompCrm.Ai.SmsTimeExtractor

  @doc """
  Returns:

    * **`{:ok, %{assistant_sms, job_operations, time_operations, emp_operations, reminder_operations}}`**
    * **`{:error, reason}`**

  **`prior_turns`** — list of **`{:contractor | :assistant, String.t()}`** oldest-first (same phone / business);
  pass **`[]`** when there is no prior thread.

  **`opts`** — keyword list; supports **`reminder_wall_tz`** (IANA) so naive **`fire_at`** values in **`reminder_actions`**
  are interpreted as that zone’s wall clock (same as SMS reminder settings). Defaults to Eastern when omitted.
  """
  def extract(
        raw_message,
        jobs_snapshot,
        open_time_entries_snapshot,
        employees_snapshot,
        prior_turns \\ [],
        opts \\ []
      )
      when is_binary(raw_message) and is_list(jobs_snapshot) and
             is_list(open_time_entries_snapshot) and
             is_list(employees_snapshot) and is_list(prior_turns) and is_list(opts) do
    mod =
      Application.get_env(
        :romp_crm,
        :sms_unified_inbound_adapter,
        __MODULE__.Anthropic
      )

    case mod.extract(
           raw_message,
           jobs_snapshot,
           open_time_entries_snapshot,
           employees_snapshot,
           prior_turns,
           opts
         ) do
      {:ok, %{} = attrs} -> parse_combined_payload(attrs, opts)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_combined_payload(map, opts) when is_map(map) and is_list(opts) do
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

    reminder_actions = Map.get(map, "reminder_actions")
    reminder_actions = if is_list(reminder_actions), do: reminder_actions, else: []

    with {:ok, job_ops} <- SmsJobExtractor.parse_actions_list(job_actions),
         {:ok, time_ops} <- SmsTimeExtractor.parse_actions_list(time_actions),
         {:ok, emp_ops} <- SmsEmployeeTimeExtractor.parse_actions_list(employee_actions),
         {:ok, rem_ops} <- SmsReminderExtractor.parse_actions_list(reminder_actions, opts) do
      {:ok,
       %{
         assistant_sms: assistant,
         job_operations: job_ops,
         time_operations: time_ops,
         emp_operations: emp_ops,
         reminder_operations: rem_ops
       }}
    end
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
