defmodule RompCrm.TimeTracking do
  import Ecto.Query
  alias RompCrm.Repo
  alias RompCrm.TimeTracking.TimeEntry

  def subscribe(business_id) when is_integer(business_id) do
    Phoenix.PubSub.subscribe(RompCrm.PubSub, topic(business_id))
  end

  defp topic(business_id), do: "time_entries:business:#{business_id}"

  @doc "All time entries for a business, newest first, with job preloaded."
  def list_time_entries(business_id) when is_integer(business_id) do
    Repo.all(
      from te in TimeEntry,
        where: te.business_id == ^business_id,
        order_by: [desc: te.started_at],
        preload: [:job]
    )
  end

  @doc "Time entries for a specific job, newest first."
  def list_time_entries_for_job(job_id, business_id) when is_integer(business_id) do
    Repo.all(
      from te in TimeEntry,
        where: te.job_id == ^job_id and te.business_id == ^business_id,
        order_by: [desc: te.started_at]
    )
  end

  def get_time_entry!(id, business_id) when is_integer(business_id) do
    Repo.get_by!(TimeEntry, id: id, business_id: business_id)
  end

  @doc "Returns the open (no ended_at) entry for a job, or nil."
  def get_open_entry_for_job(job_id, business_id) when is_integer(business_id) do
    Repo.one(
      from te in TimeEntry,
        where: te.job_id == ^job_id and te.business_id == ^business_id and is_nil(te.ended_at),
        limit: 1
    )
  end

  def create_time_entry(attrs) do
    with {:ok, entry} <- %TimeEntry{} |> TimeEntry.changeset(attrs) |> Repo.insert() do
      broadcast(entry.business_id, {:time_entry_created, entry})
      {:ok, entry}
    end
  end

  def update_time_entry(%TimeEntry{} = entry, attrs) do
    with {:ok, entry} <- entry |> TimeEntry.changeset(attrs) |> Repo.update() do
      broadcast(entry.business_id, {:time_entry_updated, entry})
      {:ok, entry}
    end
  end

  def delete_time_entry(%TimeEntry{} = entry) do
    bid = entry.business_id

    with {:ok, entry} <- Repo.delete(entry) do
      broadcast(bid, {:time_entry_deleted, entry})
      {:ok, entry}
    end
  end

  def change_time_entry(%TimeEntry{} = entry, attrs \\ %{}) do
    TimeEntry.changeset(entry, attrs)
  end

  @doc "Sum of completed entry durations for a job, in minutes."
  def total_minutes_for_job(job_id, business_id) when is_integer(business_id) do
    list_time_entries_for_job(job_id, business_id)
    |> Enum.reduce(0, fn entry, acc ->
      case TimeEntry.duration_minutes(entry) do
        nil -> acc
        mins -> acc + mins
      end
    end)
  end

  @doc "Human-readable total for a job, e.g. \"6h 30m\". Returns \"0m\" if none."
  def format_total_for_job(job_id, business_id) do
    mins = total_minutes_for_job(job_id, business_id)
    h = div(mins, 60)
    m = rem(mins, 60)

    cond do
      h == 0 -> "#{m}m"
      m == 0 -> "#{h}h"
      true -> "#{h}h #{m}m"
    end
  end

  @doc """
  Returns open time entries (no ended_at) for the business, for SMS AI context.
  Each row includes job_id, job_client_name, time_entry_id, and started_at.
  """
  def snapshot_for_sms_ai(business_id) when is_integer(business_id) do
    Repo.all(
      from te in TimeEntry,
        where: te.business_id == ^business_id and is_nil(te.ended_at),
        preload: [:job]
    )
    |> Enum.map(fn te ->
      %{
        "time_entry_id" => te.id,
        "job_id" => te.job_id,
        "job_client_name" => te.job && te.job.client_name,
        "started_at" => te.started_at && NaiveDateTime.to_iso8601(te.started_at)
      }
    end)
  end

  defp broadcast(business_id, message) do
    Phoenix.PubSub.broadcast(RompCrm.PubSub, topic(business_id), message)
  end
end
