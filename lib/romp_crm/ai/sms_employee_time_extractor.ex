defmodule RompCrm.Ai.SmsEmployeeTimeExtractor do
  @moduledoc """
  Turns free-form SMS text into employee time-tracking operations via the configured adapter.

  Operations returned in `operations`:
    - `{:emp_clock_in_by_id, employee_id, clocked_in_at}`
    - `{:emp_clock_out_by_id, employee_id, clocked_out_at}`
    - `{:emp_lunch_by_id, employee_id, lunch_start_at, lunch_end_at}`

  **`employee_id`** must come from the employees snapshot (model-chosen); there is no server-side name match fallback.

  Datetimes are **naive local wall-clock** values (same as stored in `employee_time_entries`).
  """

  @doc """
  Returns `{:ok, %{assistant_sms: nil | String.t(), operations: list}}` or `{:error, reason}`.

  `employees_snapshot` comes from `Employees.snapshot_for_sms_ai/1`.
  """
  def extract(raw_message, employees_snapshot \\ [])
      when is_binary(raw_message) and is_list(employees_snapshot) do
    mod =
      Application.get_env(
        :romp_crm,
        :sms_employee_time_extractor_adapter,
        __MODULE__.Anthropic
      )

    case mod.extract(raw_message, employees_snapshot) do
      {:ok, attrs} when is_map(attrs) -> parse_extracted_payload(attrs)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_extracted_payload(map) when is_map(map) do
    map = stringify_keys(map)
    assistant = assistant_from_map(map)

    case Map.get(map, "actions") do
      actions when is_list(actions) ->
        case parse_actions(actions) do
          {:ok, ops} -> {:ok, %{assistant_sms: assistant, operations: ops}}
          err -> err
        end

      nil ->
        {:ok, %{assistant_sms: assistant, operations: []}}

      _ ->
        {:error, :invalid_actions}
    end
  end

  defp assistant_from_map(map) do
    case Map.get(map, "assistant_sms") do
      s when is_binary(s) -> s |> String.trim() |> String.slice(0, 480)
      _ -> nil
    end
  end

  defp parse_actions([]), do: {:ok, []}

  defp parse_actions(actions) when is_list(actions) do
    Enum.reduce_while(Enum.with_index(actions, 1), {:ok, []}, fn {raw, idx}, {:ok, acc} ->
      if is_map(raw) do
        case parse_single_action(raw) do
          {:ok, op} -> {:cont, {:ok, [op | acc]}}
          {:error, reason} -> {:halt, {:error, {:invalid_action, idx, reason}}}
        end
      else
        {:halt, {:error, {:invalid_action, idx, :not_an_object}}}
      end
    end)
    |> case do
      {:ok, ops} -> {:ok, Enum.reverse(ops)}
      err -> err
    end
  end

  defp parse_actions(_), do: {:error, :invalid_actions}

  @doc false
  def parse_actions_list(actions) when is_list(actions), do: parse_actions(actions)
  def parse_actions_list(_), do: {:error, :invalid_actions}

  defp parse_single_action(map) when is_map(map) do
    map = stringify_keys(map)
    intent = map |> Map.get("intent", "") |> to_string() |> String.trim() |> String.downcase()

    case intent do
      "clock_in" -> parse_emp_clock_in(map)
      "clock_out" -> parse_emp_clock_out(map)
      "lunch" -> parse_emp_lunch(map)
      _ -> {:error, {:unknown_intent, intent}}
    end
  end

  defp parse_emp_clock_in(map) do
    with {:ok, clocked_in_at} <- parse_naive_dt(Map.get(map, "clocked_in_at")) do
      case coerce_employee_id(Map.get(map, "employee_id")) do
        {:ok, emp_id} -> {:ok, {:emp_clock_in_by_id, emp_id, clocked_in_at}}
        :missing -> {:error, :missing_employee_id}
        {:error, _} -> {:error, :invalid_employee_id}
      end
    end
  end

  defp parse_emp_clock_out(map) do
    with {:ok, clocked_out_at} <- parse_naive_dt(Map.get(map, "clocked_out_at")) do
      case coerce_employee_id(Map.get(map, "employee_id")) do
        {:ok, emp_id} -> {:ok, {:emp_clock_out_by_id, emp_id, clocked_out_at}}
        :missing -> {:error, :missing_employee_id}
        {:error, _} -> {:error, :invalid_employee_id}
      end
    end
  end

  defp parse_emp_lunch(map) do
    with {:ok, lunch_start} <- parse_naive_dt(Map.get(map, "lunch_start_at")),
         {:ok, lunch_end} <- parse_naive_dt(Map.get(map, "lunch_end_at")) do
      case coerce_employee_id(Map.get(map, "employee_id")) do
        {:ok, emp_id} -> {:ok, {:emp_lunch_by_id, emp_id, lunch_start, lunch_end}}
        :missing -> {:error, :missing_employee_id}
        {:error, _} -> {:error, :invalid_employee_id}
      end
    end
  end

  defp coerce_employee_id(nil), do: :missing
  defp coerce_employee_id(v) when v == "", do: :missing
  defp coerce_employee_id(v) when is_integer(v) and v > 0, do: {:ok, v}

  defp coerce_employee_id(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i > 0 -> {:ok, i}
      _ -> {:error, :invalid_employee_id}
    end
  end

  defp coerce_employee_id(_), do: {:error, :invalid_employee_id}

  @doc false
  def parse_naive_dt(nil), do: {:error, :missing_datetime}
  def parse_naive_dt(""), do: {:error, :missing_datetime}

  def parse_naive_dt(s) when is_binary(s) do
    case NaiveDateTime.from_iso8601(String.trim(s)) do
      {:ok, dt} -> {:ok, dt}
      {:error, _} -> {:error, {:invalid_datetime, s}}
    end
  end

  def parse_naive_dt(_), do: {:error, :invalid_datetime_type}

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
