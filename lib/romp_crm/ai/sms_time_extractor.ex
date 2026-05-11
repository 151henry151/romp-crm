defmodule RompCrm.Ai.SmsTimeExtractor do
  @moduledoc """
  Turns free-form SMS text into job time-tracking operations via the configured adapter.

  Operations returned in `operations`:
    - `{:clock_in_by_id, job_id, started_at}` — start a time entry for job by database ID.
    - `{:clock_in, match, started_at}` — start a time entry matched by job attributes.
    - `{:clock_out_by_id, job_id, ended_at}` — close the open entry for job by ID.
    - `{:clock_out, match, ended_at}` — close the open entry matched by job attributes.

  Times are `NaiveDateTime` values.
  """

  @doc """
  Returns `{:ok, %{assistant_sms: nil | String.t(), operations: list}}` or `{:error, reason}`.

  `jobs_snapshot` is the same list as used for job extraction.
  `open_entries_snapshot` comes from `TimeTracking.snapshot_for_sms_ai/1`.
  """
  def extract(raw_message, jobs_snapshot \\ [], open_entries_snapshot \\ [])
      when is_binary(raw_message) and is_list(jobs_snapshot) and is_list(open_entries_snapshot) do
    mod =
      Application.get_env(
        :romp_crm,
        :sms_time_extractor_adapter,
        __MODULE__.Anthropic
      )

    case mod.extract(raw_message, jobs_snapshot, open_entries_snapshot) do
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
          {:ok, ops} -> finalize(assistant, ops)
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

  defp finalize(assistant, ops) do
    {:ok, %{assistant_sms: assistant, operations: ops}}
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

  defp parse_single_action(map) when is_map(map) do
    map = stringify_keys(map)
    intent = map |> Map.get("intent", "") |> to_string() |> String.trim() |> String.downcase()

    case intent do
      "clock_in" -> parse_clock_in(map)
      "clock_out" -> parse_clock_out(map)
      _ -> {:error, {:unknown_intent, intent}}
    end
  end

  defp parse_clock_in(map) do
    with {:ok, started_at} <- parse_naive_dt(Map.get(map, "started_at")) do
      case coerce_job_id(Map.get(map, "job_id")) do
        {:ok, job_id} -> {:ok, {:clock_in_by_id, job_id, started_at}}
        :missing -> resolve_clock_via_match(map, :clock_in, started_at)
        {:error, _} -> {:error, :invalid_job_id}
      end
    end
  end

  defp parse_clock_out(map) do
    with {:ok, ended_at} <- parse_naive_dt(Map.get(map, "ended_at")) do
      case coerce_job_id(Map.get(map, "job_id")) do
        {:ok, job_id} -> {:ok, {:clock_out_by_id, job_id, ended_at}}
        :missing -> resolve_clock_via_match(map, :clock_out, ended_at)
        {:error, _} -> {:error, :invalid_job_id}
      end
    end
  end

  defp resolve_clock_via_match(map, intent, dt) do
    match =
      map
      |> Map.get("match", %{})
      |> stringify_keys()
      |> Map.new(fn {k, v} -> {k, nilify_blank(v)} end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(match) == 0 do
      {:error, :missing_job_id_or_match}
    else
      {:ok, {intent, match, dt}}
    end
  end

  defp coerce_job_id(nil), do: :missing
  defp coerce_job_id(v) when v == "", do: :missing
  defp coerce_job_id(v) when is_integer(v) and v > 0, do: {:ok, v}

  defp coerce_job_id(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i > 0 -> {:ok, i}
      _ -> {:error, :invalid_job_id}
    end
  end

  defp coerce_job_id(_), do: {:error, :invalid_job_id}

  @doc false
  def parse_naive_dt(nil), do: {:error, :missing_datetime}
  def parse_naive_dt(""), do: {:error, :missing_datetime}

  def parse_naive_dt(s) when is_binary(s) do
    trimmed = String.trim(s)

    case NaiveDateTime.from_iso8601(trimmed) do
      {:ok, dt} -> {:ok, dt}
      {:error, _} -> {:error, {:invalid_datetime, s}}
    end
  end

  def parse_naive_dt(_), do: {:error, :invalid_datetime_type}

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp nilify_blank(nil), do: nil
  defp nilify_blank(""), do: nil

  defp nilify_blank(v) when is_binary(v),
    do: if(String.trim(v) == "", do: nil, else: String.trim(v))

  defp nilify_blank(v), do: v
end
