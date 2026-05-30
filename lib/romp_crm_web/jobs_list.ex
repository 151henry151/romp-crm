defmodule RompCrmWeb.JobsList do
  @moduledoc """
  Filter, sort, and display helpers for the jobs list LiveView.
  """

  alias RompCrm.Jobs.Job
  alias RompCrm.Addresses

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

  def filter_active?(:all), do: false
  def filter_active?(_), do: true

  @greyscale_status_badges %{
    lead: "bg-base-200/60 text-base-content/60 dark:bg-base-300/20 dark:text-base-content/55",
    pending: "bg-base-200 text-base-content/70 dark:bg-base-300/35 dark:text-base-content/68",
    in_progress: "bg-base-300/45 text-base-content/82 dark:bg-base-300/50 dark:text-base-content/82",
    done: "bg-base-300 text-base-content/95 dark:bg-base-300/70 dark:text-base-content/95"
  }

  @greyscale_priority_high_badge "bg-base-300/55 text-base-content border border-base-content/20 font-semibold dark:bg-base-300/60 dark:text-base-content dark:border-base-content/25"

  def filter_button_label(filter, color_code?) do
    base =
      if filter_active?(filter) do
        "Filter active: #{filter_label(filter)} — not all jobs are shown"
      else
        "Filter: All jobs"
      end

    if color_code? do
      base <> " · Color-code on"
    else
      base
    end
  end

  def filter_button_label(filter), do: filter_button_label(filter, false)

  def sort_label(:name), do: "Alphabetical"
  def sort_label(:scheduled), do: "Scheduled date"
  def sort_label(:created), do: "Creation date"

  def sort_summary(sort_by, show_address_primary?) do
    base = "Sort: #{sort_label(sort_by)}"

    if show_address_primary? do
      base <> " · List by address"
    else
      base
    end
  end

  def status_label(:lead), do: "Lead"
  def status_label(:pending), do: "Pending"
  def status_label(:in_progress), do: "In Progress"
  def status_label(:done), do: "Done"

  def status_badge_class(status, false) when status in [:lead, :pending, :in_progress, :done] do
    Map.fetch!(@greyscale_status_badges, status)
  end

  def status_badge_class(:lead, true),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900/45 dark:text-blue-200"

  def status_badge_class(:pending, true),
    do: "bg-amber-100 text-amber-800 dark:bg-amber-900/45 dark:text-amber-200"

  def status_badge_class(:in_progress, true),
    do: "bg-green-100 text-green-800 dark:bg-green-900/45 dark:text-green-200"

  def status_badge_class(:done, true), do: Map.fetch!(@greyscale_status_badges, :done)

  def priority_badge_class(:high, false), do: @greyscale_priority_high_badge

  def priority_badge_class(:normal, false), do: ""

  def priority_badge_class(:high, true),
    do: "bg-red-100 text-red-800 dark:bg-red-900/45 dark:text-red-200"

  def priority_badge_class(:normal, true), do: ""

  def mobile_card_classes(%Job{priority: :high}, expanded?) do
    if expanded? do
      "border-base-content/25 bg-base-200/80 dark:border-base-content/30 dark:bg-base-300/45"
    else
      "border-base-content/25 bg-base-200 shadow-sm dark:border-base-content/30 dark:bg-base-300/40"
    end
  end

  def mobile_card_classes(_job, expanded?) do
    if expanded? do
      "border-base-300 bg-base-200/40"
    else
      "border-base-300 bg-base-100"
    end
  end

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
    Addresses.format_service(job)
  end

  def primary_heading(%Job{} = job, false) do
    job.client_name || "—"
  end

  def secondary_heading(%Job{} = job, true) do
    job.client_name
  end

  def secondary_heading(_job, false), do: nil

  def count_for(jobs, :all) when is_list(jobs), do: length(jobs)

  def count_for(jobs, status) when is_list(jobs) do
    Enum.count(jobs, &(&1.status == status))
  end
end
