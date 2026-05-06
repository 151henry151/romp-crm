defmodule JgsCrm.JobsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `JgsCrm.Jobs` context.
  """

  @doc """
  Generate a job.
  """
  def job_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        address: "some address",
        client_name: "some client_name",
        next_action: "some next_action",
        notes: "some notes",
        phone: "some phone",
        priority: "some priority",
        referred_by: "some referred_by",
        status: "some status",
        work_description: "some work_description"
      })

    {:ok, job} = JgsCrm.Jobs.create_job(scope, attrs)
    job
  end
end
