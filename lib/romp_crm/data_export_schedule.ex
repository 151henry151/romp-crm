defmodule RompCrm.DataExportSchedule do
  @moduledoc false

  @doc "UTC **`DateTime`** for the next run after **`from`** for the given schedule string."
  def compute_next_run_at(schedule, %DateTime{} = from)
      when schedule in ~w(daily weekly monthly) do
    from = DateTime.truncate(from, :second)
    seconds = interval_seconds(schedule)
    DateTime.add(from, seconds, :second)
  end

  def compute_next_run_at(_, _), do: nil

  def interval_seconds("daily"), do: 86_400
  def interval_seconds("weekly"), do: 7 * 86_400
  def interval_seconds("monthly"), do: 30 * 86_400
  def interval_seconds(_), do: nil
end
