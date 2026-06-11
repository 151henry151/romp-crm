defmodule RompCrm.Ai.CustomerBookingExtractor do
  @moduledoc """
  AI extraction for **customer-facing** booking SMS replies (separate from the
  contractor-facing unified extractor): parses the client's availability message
  against their active booking conversation(s) and returns one reply plus an
  optional scheduling action.

  Returns `{:ok, result}` with:

    * `reply_sms` — concise, warm reply to text back (may be a clarifying question)
    * `resolved_booking_link_id` — which booking conversation the client means
      (`nil` when ambiguous across businesses; the server then refuses to act)
    * `action` — `nil`, or one of:
        * `%{type: :hard_booking, starts_at: DateTime, ends_at: DateTime}`
        * `%{type: :soft_availability, availability_text: String, windows: [%{start, end}]}`
        * `%{type: :cancel_booking, booking_id: integer}`

  Configure **`customer_booking_adapter`** (tests use **`DeterministicStub`**).
  """

  @doc """
  `booking_contexts` — list of maps (one per active booking link for this phone)
  with business/job/duration/slot context. `prior_turns` — `[{:client | :assistant, text}]`
  for the relevant thread(s), oldest first.
  """
  def extract(raw_message, booking_contexts, prior_turns, opts \\ [])
      when is_binary(raw_message) and is_list(booking_contexts) and is_list(prior_turns) do
    mod = Application.get_env(:romp_crm, :customer_booking_adapter, __MODULE__.Anthropic)

    case mod.extract(raw_message, booking_contexts, prior_turns, opts) do
      {:ok, %{} = attrs} -> parse_payload(attrs)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_payload(map) do
    map = stringify_keys(map)

    reply =
      case Map.get(map, "reply_sms") do
        s when is_binary(s) -> s |> String.trim() |> String.slice(0, 480)
        _ -> ""
      end

    resolved_id = parse_optional_id(Map.get(map, "resolved_booking_link_id"))

    with {:ok, action} <- parse_action(Map.get(map, "action")) do
      {:ok, %{reply_sms: reply, resolved_booking_link_id: resolved_id, action: action}}
    end
  end

  defp parse_action(nil), do: {:ok, nil}
  defp parse_action(""), do: {:ok, nil}

  defp parse_action(%{} = raw) do
    m = stringify_keys(raw)

    case m["type"] |> to_string() |> String.trim() |> String.downcase() do
      "" ->
        {:ok, nil}

      "none" ->
        {:ok, nil}

      "hard_booking" ->
        with {:ok, starts_at} <- parse_instant(m["starts_at"]),
             {:ok, ends_at} <- parse_instant(m["ends_at"]) do
          {:ok, %{type: :hard_booking, starts_at: starts_at, ends_at: ends_at}}
        else
          _ -> {:error, :invalid_hard_booking_times}
        end

      "soft_availability" ->
        text = m["availability_text"] |> to_string() |> String.trim()
        windows = parse_windows(m["windows"])

        if text == "" do
          {:error, :missing_availability_text}
        else
          {:ok, %{type: :soft_availability, availability_text: text, windows: windows}}
        end

      "cancel_booking" ->
        case parse_optional_id(m["booking_id"]) do
          nil -> {:error, :missing_booking_id}
          id -> {:ok, %{type: :cancel_booking, booking_id: id}}
        end

      _ ->
        {:error, :unknown_booking_action_type}
    end
  end

  defp parse_action(_), do: {:error, :invalid_action}

  defp parse_windows(list) when is_list(list) do
    Enum.flat_map(list, fn
      %{} = w ->
        w = stringify_keys(w)

        with {:ok, s} <- parse_instant(w["start"]),
             {:ok, e} <- parse_instant(w["end"]) do
          [%{start: s, end: e}]
        else
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp parse_windows(_), do: []

  defp parse_instant(raw) when is_binary(raw) do
    case DateTime.from_iso8601(String.trim(raw)) do
      {:ok, dt, _} -> {:ok, DateTime.truncate(dt, :second)}
      _ -> :error
    end
  end

  defp parse_instant(_), do: :error

  defp parse_optional_id(n) when is_integer(n) and n > 0, do: n

  defp parse_optional_id(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp parse_optional_id(_), do: nil

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
