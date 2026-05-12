defmodule RompCrmWeb.JobTimeLogDefaults do
  @moduledoc false

  @doc """
  Default **`datetime-local`** strings for “log hours on this job” (start rounded down to 15 minutes, end +1 hour).
  """
  def default_datetime_local_pair do
    now = NaiveDateTime.utc_now(:second)
    start_ndt = round_down_quarter(now)
    end_ndt = NaiveDateTime.add(start_ndt, 3600, :second)
    {to_datetime_local(start_ndt), to_datetime_local(end_ndt)}
  end

  defp round_down_quarter(%NaiveDateTime{} = ndt) do
    m = div(ndt.minute, 15) * 15
    %{ndt | minute: m, second: 0, microsecond: {0, 0}}
  end

  defp to_datetime_local(%NaiveDateTime{} = ndt) do
    :io_lib.format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w", [
      ndt.year,
      ndt.month,
      ndt.day,
      ndt.hour,
      ndt.minute
    ])
    |> IO.iodata_to_binary()
  end
end
