defmodule RompCrm.Scheduling.InternalJobsSource do
  @moduledoc """
  Always-on `CalendarSource` over RompCRM's own data: scheduled jobs (date plus
  time) and confirmed bookings for a business.

  Jobs carry no duration, so blocks use `@default_job_minutes`. Jobs scheduled
  with a date but no time are not treated as busy — the technician has not
  committed to a clock time yet.
  """

  @behaviour RompCrm.Scheduling.CalendarSource

  import Ecto.Query

  alias RompCrm.Bookings.Booking
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo

  @default_job_minutes 120

  @impl true
  def fetch_busy_blocks(%{business_id: business_id} = credential, {from_date, to_date}, timezone)
      when is_integer(business_id) do
    job_minutes = Map.get(credential, :default_job_minutes, @default_job_minutes)

    blocks =
      job_blocks(business_id, from_date, to_date, timezone, job_minutes) ++
        booking_blocks(business_id, from_date, to_date)

    {:ok, Enum.sort_by(blocks, & &1.start, DateTime)}
  end

  defp job_blocks(business_id, from_date, to_date, timezone, job_minutes) do
    Repo.all(
      from j in Job,
        where: j.business_id == ^business_id,
        where: not is_nil(j.scheduled_on) and not is_nil(j.scheduled_time),
        where: j.scheduled_on >= ^from_date and j.scheduled_on <= ^to_date,
        select: {j.scheduled_on, j.scheduled_time}
    )
    |> Enum.flat_map(fn {date, time} ->
      case DateTime.new(date, time, timezone) do
        {:ok, local} ->
          start_utc = DateTime.shift_zone!(local, "Etc/UTC")
          [%{start: start_utc, end: DateTime.add(start_utc, job_minutes * 60, :second)}]

        {:gap, _before, after_dt} ->
          start_utc = DateTime.shift_zone!(after_dt, "Etc/UTC")
          [%{start: start_utc, end: DateTime.add(start_utc, job_minutes * 60, :second)}]

        {:ambiguous, first, _second} ->
          start_utc = DateTime.shift_zone!(first, "Etc/UTC")
          [%{start: start_utc, end: DateTime.add(start_utc, job_minutes * 60, :second)}]

        _ ->
          []
      end
    end)
  end

  defp booking_blocks(business_id, from_date, to_date) do
    # Widen by a day on each side so timezone offsets cannot drop edge bookings.
    span_start = DateTime.new!(Date.add(from_date, -1), ~T[00:00:00], "Etc/UTC")
    span_end = DateTime.new!(Date.add(to_date, 2), ~T[00:00:00], "Etc/UTC")

    Repo.all(
      from b in Booking,
        where: b.business_id == ^business_id,
        where: b.status == "confirmed",
        where: b.starts_at < ^span_end and b.ends_at > ^span_start,
        select: %{start: b.starts_at, end: b.ends_at}
    )
  end
end
