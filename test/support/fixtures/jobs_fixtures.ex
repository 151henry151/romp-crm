defmodule JgsCrm.JobsFixtures do
  @moduledoc """
  Test helpers for creating jobs via `JgsCrm.Jobs`.
  """

  @doc """
  Creates a job with default attributes; merges `attrs` when given.
  """
  def job_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        address: "some address",
        client_name: "some client_name",
        next_action: "some next_action",
        notes: "some notes",
        phone: "some phone",
        priority: :normal,
        referred_by: "some referred_by",
        status: :lead,
        work_description: "some work_description"
      })

    {:ok, job} = JgsCrm.Jobs.create_job(attrs)
    job
  end
end
