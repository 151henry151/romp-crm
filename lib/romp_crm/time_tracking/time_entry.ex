defmodule RompCrm.TimeTracking.TimeEntry do
  @moduledoc """
  Job-level clock in/out rows.

  **`started_at`** and **`ended_at`** are **naive** datetimes: treat them as the contractor's local
  wall-clock times (the app does not perform timezone conversion).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "time_entries" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :job, RompCrm.Jobs.Job

    field :started_at, :naive_datetime
    field :ended_at, :naive_datetime
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:business_id, :job_id, :started_at, :ended_at, :notes])
    |> validate_required([:business_id, :job_id, :started_at])
    |> unique_constraint([:business_id, :job_id],
          name: :time_entries_one_open_clock_per_job
        )
  end

  @doc "Duration in minutes between started_at and ended_at. nil if entry is still open."
  def duration_minutes(%__MODULE__{started_at: s, ended_at: e})
      when not is_nil(s) and not is_nil(e) do
    NaiveDateTime.diff(e, s) |> div(60)
  end

  def duration_minutes(_), do: nil

  @doc "Human-readable duration string, e.g. \"6h 30m\". nil if entry is still open."
  def format_duration(entry) do
    case duration_minutes(entry) do
      nil ->
        nil

      mins ->
        h = div(mins, 60)
        m = rem(mins, 60)

        cond do
          h == 0 -> "#{m}m"
          m == 0 -> "#{h}h"
          true -> "#{h}h #{m}m"
        end
    end
  end
end
