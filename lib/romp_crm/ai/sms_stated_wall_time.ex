defmodule RompCrm.Ai.SmsStatedWallTime do
  @moduledoc """
  Deterministic spoken wall-clock times from contractor SMS.

  Models sometimes copy prior-day times from employee `recent_entries` instead of
  the time stated in the latest SMS. When the inbound text clearly states exactly
  one clock time, we override disagreeing punch timestamps and rewrite the
  confirmation SMS accordingly.
  """

  @am_pm_time_re ~r/\b(\d{1,2})(?::(\d{2}))?\s*(a\.?\s*m\.?|p\.?\s*m\.?)\b/i
  @noon_re ~r/\bnoon\b/i
  @midnight_re ~r/\bmidnight\b/i

  @doc """
  Extract unique wall-clock times from free-form SMS, in order of first appearance.

  Only 12-hour times with am/pm (plus noon/midnight) are recognized so ISO
  datetimes like `2026-07-28T08:30:00` in stub JSON do not count.
  """
  def extract_times(text) when is_binary(text) do
    text
    |> collect_matches()
    |> Enum.uniq()
  end

  @doc """
  When `raw_message` states exactly one clock time, replace punch timestamps on
  employee/job clock-in and clock-out ops that disagree, and rewrite matching
  times in `assistant_sms`.
  """
  def apply_to_result(result, raw_message)
      when is_map(result) and is_binary(raw_message) do
    case extract_times(raw_message) do
      [stated] ->
        {emp_ops, emp_replaced} =
          override_ops(Map.get(result, :emp_operations) || [], stated)

        {time_ops, time_replaced} =
          override_ops(Map.get(result, :time_operations) || [], stated)

        replaced = emp_replaced ++ time_replaced

        assistant =
          rewrite_assistant(Map.get(result, :assistant_sms), replaced, stated)

        result
        |> Map.put(:emp_operations, emp_ops)
        |> Map.put(:time_operations, time_ops)
        |> Map.put(:assistant_sms, assistant)

      _ ->
        result
    end
  end

  defp collect_matches(text) do
    am_pm_pos =
      Regex.scan(@am_pm_time_re, text)
      |> Enum.zip(Regex.scan(@am_pm_time_re, text, return: :index))
      |> Enum.flat_map(fn {capture, [{start, _} | _]} ->
        case parse_am_pm_match(capture) do
          nil -> []
          time -> [{start, time}]
        end
      end)

    noon_pos =
      case Regex.run(@noon_re, text, return: :index) do
        [{start, _}] -> [{start, ~T[12:00:00]}]
        _ -> []
      end

    midnight_pos =
      case Regex.run(@midnight_re, text, return: :index) do
        [{start, _}] -> [{start, ~T[00:00:00]}]
        _ -> []
      end

    (am_pm_pos ++ noon_pos ++ midnight_pos)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp parse_am_pm_match([_whole, hour_s, minute_s, meridiem]) do
    with {hour0, ""} <- Integer.parse(hour_s),
         minute when minute >= 0 <- parse_minute(minute_s),
         {:ok, hour24} <- to_24h(hour0, meridiem),
         {:ok, time} <- Time.new(hour24, minute, 0) do
      time
    else
      _ -> nil
    end
  end

  defp parse_am_pm_match(_), do: nil

  defp parse_minute(nil), do: 0
  defp parse_minute(""), do: 0

  defp parse_minute(s) when is_binary(s) do
    case Integer.parse(s) do
      {m, ""} when m in 0..59 -> m
      _ -> -1
    end
  end

  defp to_24h(hour, meridiem) when hour in 1..12 do
    mer = meridiem |> String.downcase() |> String.replace(~r/[^ap]/, "")

    cond do
      String.starts_with?(mer, "a") and hour == 12 -> {:ok, 0}
      String.starts_with?(mer, "a") -> {:ok, hour}
      String.starts_with?(mer, "p") and hour == 12 -> {:ok, 12}
      String.starts_with?(mer, "p") -> {:ok, hour + 12}
      true -> :error
    end
  end

  defp to_24h(_, _), do: :error

  defp override_ops(ops, stated) when is_list(ops) do
    Enum.map_reduce(ops, [], fn op, acc ->
      case override_op(op, stated) do
        {^op, nil} -> {op, acc}
        {new_op, {from, to}} -> {new_op, [{from, to} | acc]}
      end
    end)
    |> then(fn {ops, replaced} -> {ops, Enum.reverse(replaced)} end)
  end

  defp override_op({:emp_clock_in_by_id, id, at}, stated),
    do: replace_dt({:emp_clock_in_by_id, id, at}, at, stated, fn new -> {:emp_clock_in_by_id, id, new} end)

  defp override_op({:emp_clock_out_by_id, id, at}, stated),
    do: replace_dt({:emp_clock_out_by_id, id, at}, at, stated, fn new -> {:emp_clock_out_by_id, id, new} end)

  defp override_op({:clock_in_by_id, id, at}, stated),
    do: replace_dt({:clock_in_by_id, id, at}, at, stated, fn new -> {:clock_in_by_id, id, new} end)

  defp override_op({:clock_out_by_id, id, at}, stated),
    do: replace_dt({:clock_out_by_id, id, at}, at, stated, fn new -> {:clock_out_by_id, id, new} end)

  defp override_op(op, _stated), do: {op, nil}

  defp replace_dt(op, %NaiveDateTime{} = at, %Time{} = stated, build) do
    current = Time.new!(at.hour, at.minute, 0)

    if Time.compare(current, stated) == :eq do
      {op, nil}
    else
      new_at = %{at | hour: stated.hour, minute: stated.minute, second: 0}
      {build.(new_at), {current, stated}}
    end
  end

  defp rewrite_assistant(nil, _replaced, _stated), do: nil
  defp rewrite_assistant(sms, [], _stated) when is_binary(sms), do: sms

  defp rewrite_assistant(sms, replaced, stated) when is_binary(sms) do
    Enum.reduce(replaced, sms, fn {from, _to}, acc ->
      rewrite_time_in_text(acc, from, stated)
    end)
  end

  defp rewrite_assistant(other, _, _), do: other

  defp rewrite_time_in_text(text, %Time{} = from, %Time{} = to) do
    {h12, mer} = twelve_hour(from)
    to_label = format_12h(to)
    mer_pat = meridiem_pattern(mer)

    patterns = [
      ~r/\b#{h12}:#{pad2(from.minute)}\s*#{mer_pat}\b/i,
      ~r/\b#{h12}:#{pad2(from.minute)}#{mer_pat}\b/i
    ]

    Enum.reduce(patterns, text, fn re, acc ->
      Regex.replace(re, acc, to_label)
    end)
  end

  defp twelve_hour(%Time{hour: h}) do
    cond do
      h == 0 -> {12, :am}
      h < 12 -> {h, :am}
      h == 12 -> {12, :pm}
      true -> {h - 12, :pm}
    end
  end

  defp format_12h(%Time{} = t) do
    {h12, mer} = twelve_hour(t)
    suffix = if mer == :am, do: "AM", else: "PM"
    "#{h12}:#{pad2(t.minute)} #{suffix}"
  end

  defp meridiem_pattern(:am), do: "a\\.?\\s*m\\.?"
  defp meridiem_pattern(:pm), do: "p\\.?\\s*m\\.?"

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)
end
