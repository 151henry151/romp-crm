defmodule RompCrmWeb.JobsList do
  @moduledoc """
  Filter, sort, and display helpers for the jobs list LiveView.
  """

  alias RompCrm.Jobs.Job

  @type filter :: :all | :lead | :pending | :in_progress | :done
  @type sort_by :: :name | :scheduled | :created

  @filter_options [
    {"All", :all},
    {"Lead", :lead},
    {"Pending", :pending},
    {"In Progress", :in_progress},
    {"Done", :done}
  ]

  @sort_options [
    {"Alphabetical", :name},
    {"Scheduled date", :scheduled},
    {"Creation date", :created}
  ]

  def filter_options, do: @filter_options
  def sort_options, do: @sort_options

  def filter_label(:all), do: "All"
  def filter_label(status) when status in [:lead, :pending, :in_progress, :done], do: status_label(status)

  def sort_label(:name), do: "Alphabetical"
  def sort_label(:scheduled), do: "Scheduled date"
  def sort_label(:created), do: "Creation date"

  def status_label(:lead), do: "Lead"
  def status_label(:pending), do: "Pending"
  def status_label(:in_progress), do: "In Progress"
  def status_label(:done), do: "Done"

  def prepare_jobs(jobs, filter, sort_by) when is_list(jobs) do
    jobs
    |> filter_jobs(filter)
    |> sort_jobs(sort_by)
  end

  def filter_jobs(jobs, :all), do: jobs

  def filter_jobs(jobs, status) when status in [:lead, :pending, :in_progress, :done] do
    Enum.filter(jobs, &(&1.status == status))
  end

  def sort_jobs(jobs, :name) do
    Enum.sort_by(jobs, fn job -> (job.client_name || "") |> String.downcase() end)
  end

  def sort_jobs(jobs, :created) do
    Enum.sort_by(jobs, fn job -> job.inserted_at end, {:desc, DateTime})
  end

  def sort_jobs(jobs, :scheduled) do
    Enum.sort_by(jobs, fn job ->
      case effective_schedule_date(job) do
        nil -> {1, ~D[9999-12-31]}
        date -> {0, date}
      end
    end)
  end

  @doc """
  Soonest schedule date for a job: minimum of job `scheduled_on` and each work item's `scheduled_on`.
  """
  def effective_schedule_date(%Job{} = job) do
    job_dates =
      (job.work_items || [])
      |> Enum.map(& &1.scheduled_on)
      |> Enum.reject(&is_nil/1)

    dates =
      case job.scheduled_on do
        nil -> job_dates
        d -> [d | job_dates]
      end

    case dates do
      [] -> nil
      list -> Enum.min(list, Date)
    end
  end

  def primary_heading(%Job{} = job, true) do
    display_address(job.address)
  end

  def primary_heading(%Job{} = job, false) do
    job.client_name || "—"
  end

  def secondary_heading(%Job{} = job, true) do
    job.client_name
  end

  def secondary_heading(_job, false), do: nil

  defp display_address(nil), do: "—"
  defp display_address(""), do: "—"
  defp display_address(address), do: address

  def count_for(jobs, :all) when is_list(jobs), do: length(jobs)

  def count_for(jobs, status) when is_list(jobs) do
    Enum.count(jobs, &(&1.status == status))
  end
end
