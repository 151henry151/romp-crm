defmodule RompCrm.Bookings.JobScheduleSync do
  @moduledoc """
  When a booking is confirmed, copy the appointment onto the linked job and its
  work items (date, time, status lead → pending).
  """

  require Logger

  alias RompCrm.Bookings.{Booking, BookingLink}
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo
  alias RompCrm.Scheduling.Prefs
  alias RompCrm.Accounts.User

  @doc """
  Updates the job linked to `booking` (directly or via its booking link).
  Returns `{:ok, job}` or `:skipped`.
  """
  def sync_from_booking(%Booking{} = booking) do
    with %BookingLink{} = link <- resolve_link(booking),
         job_id when is_integer(job_id) <- link.job_id || booking.job_id,
         %Job{} = job <- Jobs.get_job(job_id, booking.business_id) do
      apply_schedule(job, link, booking)
    else
      _ -> :skipped
    end
  end

  defp resolve_link(%Booking{booking_link_id: nil}), do: nil

  defp resolve_link(%Booking{booking_link_id: link_id}) do
    case Repo.get(BookingLink, link_id) do
      %BookingLink{} = link -> link
      _ -> nil
    end
  end

  defp apply_schedule(%Job{} = job, %BookingLink{} = link, %Booking{} = booking) do
    tz = technician_timezone(booking.technician_user_id)
    local = DateTime.shift_zone!(booking.starts_at, tz)
    date_iso = local |> DateTime.to_date() |> Date.to_iso8601()
    time_hhmm = format_hhmm(local)

    job = Repo.preload(job, :work_items)

    status =
      case job.status do
        :lead -> "pending"
        other -> to_string(other)
      end

    wi_attrs = %{"scheduled_on" => date_iso, "scheduled_time" => time_hhmm}

    with {:ok, job} <-
           Jobs.update_job(job, %{
             "status" => status,
             "scheduled_on" => date_iso,
             "scheduled_time" => time_hhmm
           }),
         {:ok, job} <- sync_work_items(job, link, wi_attrs) do
      {:ok, job}
    else
      {:error, reason} ->
        Logger.warning(
          "JobScheduleSync failed job_id=#{job.id} booking_id=#{booking.id} reason=#{inspect(reason)}"
        )

        :skipped
    end
  end

  defp sync_work_items(%Job{} = job, %BookingLink{} = link, wi_attrs) do
    job = Repo.preload(job, :work_items, force: true)

    case job.work_items || [] do
      [] ->
        case Jobs.add_job_work_item(job, %{
               "title" => link.job_type_label || job.work_description || "Service visit",
               "scheduled_on" => wi_attrs["scheduled_on"],
               "scheduled_time" => wi_attrs["scheduled_time"]
             }) do
          {:ok, {updated, _wi}} -> {:ok, updated}
          {:error, reason} -> {:error, reason}
        end

      items ->
        items
        |> Enum.reduce_while({:ok, job}, fn wi, {:ok, current} ->
          case Jobs.update_job_work_item(current, wi.id, wi_attrs) do
            {:ok, updated} -> {:cont, {:ok, updated}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp technician_timezone(user_id) do
    case Repo.get(User, user_id) do
      %User{scheduling_prefs_json: json} when is_binary(json) ->
        Prefs.decode(json).timezone

      _ ->
        Prefs.default().timezone
    end
  end

  defp format_hhmm(%DateTime{} = dt) do
    dt.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    |> then(fn hh ->
      mm = dt.minute |> Integer.to_string() |> String.pad_leading(2, "0")
      hh <> ":" <> mm
    end)
  end
end
