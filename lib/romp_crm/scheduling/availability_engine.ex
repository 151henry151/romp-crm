defmodule RompCrm.Scheduling.AvailabilityEngine do
  @moduledoc """
  Pure slot computation over busy blocks.

  All blocks/windows are `%{start: DateTime, end: DateTime}` in UTC. Working hours
  and work days come from `RompCrm.Scheduling.Prefs` and are interpreted in the
  technician's timezone; results are returned in UTC.

  Busy blocks come from any number of `RompCrm.Scheduling.CalendarSource`
  implementations (internal jobs/bookings, Google freebusy, Apple CalDAV) and are
  treated identically regardless of source.
  """

  alias RompCrm.Scheduling.Prefs

  @default_step_minutes 30

  @typedoc "A half-open `[start, end)` UTC interval."
  @type block :: %{start: DateTime.t(), end: DateTime.t()}

  @doc "Sorts and merges overlapping or adjacent blocks into a minimal disjoint list."
  @spec merge_busy_blocks([block]) :: [block]
  def merge_busy_blocks(blocks) do
    blocks
    |> Enum.sort_by(& &1.start, DateTime)
    |> Enum.reduce([], fn b, acc ->
      case acc do
        [prev | rest] ->
          if DateTime.compare(b.start, prev.end) != :gt do
            merged_end = if DateTime.compare(b.end, prev.end) == :gt, do: b.end, else: prev.end
            [%{start: prev.start, end: merged_end} | rest]
          else
            [b | acc]
          end

        [] ->
          [b]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Bookable slots of `duration_minutes`, stepping every `:step_minutes` (default
  #{@default_step_minutes}) within free windows between `from_date` and `to_date`
  (dates in the technician's timezone, inclusive).

  Busy blocks are expanded by `prefs.buffer_minutes` on both sides before slots
  are computed; non-work hours/days are excluded via `working_hours_busy_blocks/3`.
  """
  @spec available_slots([block], Date.t(), Date.t(), Prefs.t(), pos_integer(), keyword()) :: [block]
  def available_slots(busy_blocks, %Date{} = from_date, %Date{} = to_date, %Prefs{} = prefs, duration_minutes, opts \\ []) do
    step = Keyword.get(opts, :step_minutes, @default_step_minutes)

    busy_blocks
    |> free_windows(from_date, to_date, prefs)
    |> Enum.flat_map(&slots_in_window(&1, duration_minutes, step))
  end

  @doc "Free windows after subtracting buffered busy blocks and non-working hours."
  @spec free_windows([block], Date.t(), Date.t(), Prefs.t()) :: [block]
  def free_windows(busy_blocks, %Date{} = from_date, %Date{} = to_date, %Prefs{} = prefs) do
    effective_busy =
      merge_busy_blocks(
        expand_blocks(busy_blocks, prefs.buffer_minutes) ++
          working_hours_busy_blocks(from_date, to_date, prefs)
      )

    span_start = local_datetime(from_date, ~T[00:00:00], prefs.timezone)
    span_end = local_datetime(Date.add(to_date, 1), ~T[00:00:00], prefs.timezone)

    invert_blocks(effective_busy, span_start, span_end)
  end

  @doc """
  Classifies a proposed window against busy blocks:

    * `:available` — no busy overlap inside the window
    * `:partial` — some overlap, but a contiguous free run of at least
      `duration_minutes` remains inside the window
    * `:conflict` — no free run of `duration_minutes` fits

  """
  @spec check_conflict([block], block, pos_integer()) :: :available | :partial | :conflict
  def check_conflict(busy_blocks, %{start: w_start, end: w_end} = _window, duration_minutes) do
    overlapping =
      busy_blocks
      |> merge_busy_blocks()
      |> Enum.filter(fn b ->
        DateTime.compare(b.start, w_end) == :lt and DateTime.compare(b.end, w_start) == :gt
      end)

    cond do
      overlapping == [] ->
        :available

      Enum.any?(
        invert_blocks(overlapping, w_start, w_end),
        &(block_minutes(&1) >= duration_minutes)
      ) ->
        :partial

      true ->
        :conflict
    end
  end

  @doc """
  The complement of working hours as busy blocks (UTC) for the date span: whole
  non-work days plus nightly off-hours on work days.
  """
  @spec working_hours_busy_blocks(Date.t(), Date.t(), Prefs.t()) :: [block]
  def working_hours_busy_blocks(%Date{} = from_date, %Date{} = to_date, %Prefs{} = prefs) do
    from_date
    |> Date.range(to_date)
    |> Enum.flat_map(fn date ->
      day_start = local_datetime(date, ~T[00:00:00], prefs.timezone)
      day_end = local_datetime(Date.add(date, 1), ~T[00:00:00], prefs.timezone)

      if Date.day_of_week(date) in prefs.work_days do
        work_start = local_datetime(date, prefs.workday_start, prefs.timezone)
        work_end = local_datetime(date, prefs.workday_end, prefs.timezone)

        [%{start: day_start, end: work_start}, %{start: work_end, end: day_end}]
      else
        [%{start: day_start, end: day_end}]
      end
    end)
    |> Enum.reject(&(DateTime.compare(&1.start, &1.end) != :lt))
    |> merge_busy_blocks()
  end

  defp slots_in_window(%{start: w_start, end: w_end}, duration_minutes, step_minutes) do
    Stream.iterate(w_start, &DateTime.add(&1, step_minutes * 60, :second))
    |> Stream.map(fn start -> %{start: start, end: DateTime.add(start, duration_minutes * 60, :second)} end)
    |> Enum.take_while(fn slot -> DateTime.compare(slot.end, w_end) != :gt end)
  end

  defp expand_blocks(blocks, 0), do: blocks

  defp expand_blocks(blocks, buffer_minutes) do
    seconds = buffer_minutes * 60

    Enum.map(blocks, fn b ->
      %{start: DateTime.add(b.start, -seconds, :second), end: DateTime.add(b.end, seconds, :second)}
    end)
  end

  defp invert_blocks(merged_busy, span_start, span_end) do
    {free, cursor} =
      Enum.reduce(merged_busy, {[], span_start}, fn b, {free, cursor} ->
        clipped_start = dt_max(b.start, span_start)
        clipped_end = dt_min(b.end, span_end)

        cond do
          DateTime.compare(clipped_start, clipped_end) != :lt ->
            {free, cursor}

          DateTime.compare(cursor, clipped_start) == :lt ->
            {[%{start: cursor, end: clipped_start} | free], dt_max(cursor, clipped_end)}

          true ->
            {free, dt_max(cursor, clipped_end)}
        end
      end)

    free =
      if DateTime.compare(cursor, span_end) == :lt do
        [%{start: cursor, end: span_end} | free]
      else
        free
      end

    Enum.reverse(free)
  end

  defp block_minutes(%{start: s, end: e}), do: div(DateTime.diff(e, s, :second), 60)

  defp dt_max(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
  defp dt_min(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

  # Resolves a wall-clock time in `tz` to UTC; DST gaps take the later side,
  # ambiguous times the earlier side.
  defp local_datetime(%Date{} = date, %Time{} = time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:gap, _before, after_dt} -> DateTime.shift_zone!(after_dt, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
    end
  end
end
