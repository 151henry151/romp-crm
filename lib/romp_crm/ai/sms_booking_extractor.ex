defmodule RompCrm.Ai.SmsBookingExtractor do
  @moduledoc false

  alias RompCrm.Ai.SmsReminderExtractor

  @default_min_minutes 60
  @default_max_minutes 120

  @doc """
  Parses **`booking_actions`** from unified inbound SMS extraction into typed ops:

    * `{:booking_initiate, attrs}` — start a client booking conversation
    * `{:booking_update_duration, link_id, min_minutes, max_minutes}`
    * `{:booking_confirm_soft, request_id, starts_at, ends_at}`
    * `{:booking_cancel, booking_id, reason | nil}`

  **`opts`**: **`wall_tz`** — IANA zone for naive `starts_at`/`ends_at` strings
  (defaults to Eastern, same convention as reminder times).
  """
  def parse_actions_list(list, opts \\ [])

  def parse_actions_list(nil, _opts), do: {:ok, []}

  def parse_actions_list(list, opts) when is_list(list) do
    tz = Keyword.get(opts, :wall_tz) |> to_string() |> String.trim()
    tz = if tz == "", do: "America/New_York", else: tz

    parse_actions(list, 1, [], tz)
  end

  def parse_actions_list(_, _), do: {:error, :invalid_booking_actions}

  defp parse_actions([], _idx, acc, _tz), do: {:ok, Enum.reverse(acc)}

  defp parse_actions([raw | rest], idx, acc, tz) do
    if is_map(raw) do
      case parse_one(stringify_keys(raw), tz) do
        {:ok, op} -> parse_actions(rest, idx + 1, [op | acc], tz)
        {:error, reason} -> {:error, {:invalid_booking_action, idx, reason}}
      end
    else
      {:error, {:invalid_booking_action, idx, :not_an_object}}
    end
  end

  defp parse_one(m, tz) do
    case m["intent"] |> to_string() |> String.trim() |> String.downcase() do
      "initiate" -> parse_initiate(m)
      "update_duration" -> parse_update_duration(m)
      "confirm_soft" -> parse_confirm_soft(m, tz)
      "cancel" -> parse_cancel(m)
      _ -> {:error, :unknown_booking_intent}
    end
  end

  defp parse_initiate(m) do
    phone = nilify_blank(m["phone"])

    if is_nil(phone) do
      {:error, :missing_phone}
    else
      {:ok,
       {:booking_initiate,
        %{
          client_id: parse_optional_id(m["client_id"]),
          client_name: nilify_blank(m["client_name"]) || "",
          phone: phone,
          job_id: parse_optional_id(m["job_id"]),
          job_type_label: nilify_blank(m["job_type_label"]) || "",
          duration_min_minutes: parse_minutes(m["duration_min_minutes"], @default_min_minutes),
          duration_max_minutes: parse_minutes(m["duration_max_minutes"], @default_max_minutes)
        }}}
    end
  end

  defp parse_update_duration(m) do
    link_id = parse_optional_id(m["booking_link_id"])
    min = parse_minutes(m["duration_min_minutes"], nil)
    max = parse_minutes(m["duration_max_minutes"], nil)

    cond do
      is_nil(link_id) -> {:error, :missing_booking_link_id}
      is_nil(min) or is_nil(max) -> {:error, :missing_duration}
      true -> {:ok, {:booking_update_duration, link_id, min, max}}
    end
  end

  defp parse_confirm_soft(m, tz) do
    request_id = parse_optional_id(m["booking_request_id"])

    with false <- is_nil(request_id),
         {:ok, starts_at} <- parse_instant(m["starts_at"], tz),
         {:ok, ends_at} <- parse_instant(m["ends_at"], tz) do
      {:ok, {:booking_confirm_soft, request_id, starts_at, ends_at}}
    else
      true -> {:error, :missing_booking_request_id}
      _ -> {:error, :invalid_confirm_times}
    end
  end

  defp parse_cancel(m) do
    case parse_optional_id(m["booking_id"]) do
      nil -> {:error, :missing_booking_id}
      id -> {:ok, {:booking_cancel, id, nilify_blank(m["reason"])}}
    end
  end

  defp parse_instant(raw, tz) when is_binary(raw) do
    s = String.trim(raw)

    case DateTime.from_iso8601(s) do
      {:ok, dt, _} ->
        {:ok, DateTime.truncate(dt, :second)}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(s) do
          {:ok, naive} -> SmsReminderExtractor.naive_wall_to_utc(naive, tz)
          :error -> :error
        end
    end
  end

  defp parse_instant(_, _), do: :error

  defp parse_minutes(n, _fallback) when is_integer(n) and n > 0 and n <= 24 * 60, do: n

  defp parse_minutes(n, fallback) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i > 0 and i <= 24 * 60 -> i
      _ -> fallback
    end
  end

  defp parse_minutes(_, fallback), do: fallback

  defp parse_optional_id(n) when is_integer(n) and n > 0, do: n

  defp parse_optional_id(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp parse_optional_id(_), do: nil

  defp nilify_blank(v) when v in [nil, ""], do: nil

  defp nilify_blank(v) do
    t = v |> to_string() |> String.trim()
    if t == "", do: nil, else: t
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
