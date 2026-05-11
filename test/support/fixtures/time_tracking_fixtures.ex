defmodule RompCrm.TimeTrackingFixtures do
  @moduledoc "Test helpers for creating time entries via `RompCrm.TimeTracking`."

  alias RompCrm.JobsFixtures
  alias RompCrm.TimeTracking

  @doc "Creates a time entry with defaults. Pass `:job_id` and `:business_id` to reuse existing."
  def time_entry_fixture(attrs \\ %{}) do
    {job_id, business_id, attrs} =
      case {Map.pop(attrs, :job_id), Map.pop(attrs, :business_id)} do
        {{nil, attrs}, {nil, attrs2}} ->
          job = JobsFixtures.job_fixture()
          {job.id, job.business_id, Map.merge(attrs, attrs2)}

        {{job_id, attrs}, {nil, attrs2}} ->
          job = RompCrm.Jobs.get_job!(job_id, Map.get(attrs2, :business_id, job_id))
          {job_id, job.business_id, Map.merge(attrs, attrs2)}

        {{nil, attrs}, {bid, attrs2}} ->
          job = JobsFixtures.job_fixture(%{business_id: bid})
          {job.id, bid, Map.merge(attrs, attrs2)}

        {{job_id, attrs}, {bid, attrs2}} ->
          {job_id, bid, Map.merge(attrs, attrs2)}
      end

    started_at =
      Map.get(attrs, :started_at, ~N[2026-05-11 08:00:00])

    final_attrs =
      Enum.into(attrs, %{
        business_id: business_id,
        job_id: job_id,
        started_at: started_at
      })

    {:ok, entry} = TimeTracking.create_time_entry(final_attrs)
    entry
  end
end
