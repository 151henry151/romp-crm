defmodule RompCrm.Ai.SmsReminderExtractor do
  @moduledoc false

  @doc """
  Parses **`reminder_actions`** from unified inbound SMS extraction.

  Returns **`{:reminder_schedule, fire_at, body, job_id | nil, metadata}`** tuples.
  """
  def parse_actions_list(nil), do: {:ok, []}
  def parse_actions_list(list) when is_list(list), do: parse_actions(list, 1, [])
  def parse_actions_list(_), do: {:error, :invalid_reminder_actions}

  defp parse_actions([], _idx, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_actions([raw | rest], idx, acc) do
    if is_map(raw) do
      m = stringify_keys(raw)

      case parse_one(m) do
        {:ok, op} -> parse_actions(rest, idx + 1, [op | acc])
        {:error, reason} -> {:error, {:invalid_reminder_action, idx, reason}}
      end
    else
      {:error, {:invalid_reminder_action, idx, :not_an_object}}
    end
  end

  defp parse_one(m) do
    intent = m["intent"] |> to_string() |> String.trim() |> String.downcase()

    if intent != "schedule" do
      {:error, :unknown_reminder_intent}
    else
      body = nilify_blank(m["body"])

      cond do
        body in [nil, ""] ->
          {:error, :reminder_missing_body}

        true ->
          case parse_fire_at(m["fire_at"]) do
            {:ok, %DateTime{} = dt} ->
              job_id = parse_optional_job_id(m["job_id"])
              meta = if is_map(m["metadata"]), do: m["metadata"], else: %{}
              meta = stringify_keys(meta)
              {:ok, {:reminder_schedule, dt, body, job_id, meta}}

            :error ->
              {:error, :reminder_invalid_fire_at}
          end
      end
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp nilify_blank(v) when v in [nil, ""], do: nil

  defp nilify_blank(v) when is_binary(v) do
    t = String.trim(v)
    if t == "", do: nil, else: t
  end

  defp nilify_blank(v) do
    t = v |> to_string() |> String.trim()
    if t == "", do: nil, else: t
  end

  defp parse_optional_job_id(nil), do: nil
  defp parse_optional_job_id(""), do: nil
  defp parse_optional_job_id(n) when is_integer(n) and n > 0, do: n

  defp parse_optional_job_id(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp parse_optional_job_id(_), do: nil

  defp parse_fire_at(raw) when is_binary(raw) do
    s = String.trim(raw)

    case DateTime.from_iso8601(s) do
      {:ok, dt, _} ->
        {:ok, DateTime.truncate(dt, :second)}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(s) do
          {:ok, n} ->
            {:ok, n |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)}

          :error ->
            :error
        end
    end
  end

  defp parse_fire_at(_), do: :error
end
