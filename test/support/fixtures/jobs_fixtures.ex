defmodule JgsCrm.JobsFixtures do
  @moduledoc """
  Test helpers for creating jobs via `JgsCrm.Jobs`.
  """

  alias JgsCrm.AccountsFixtures
  alias JgsCrm.Businesses

  @doc """
  Creates a business owned by a fresh user unless `:owner_user` is passed.
  """
  def business_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :owner_user) || AccountsFixtures.user_fixture()
    attrs = Map.drop(attrs, [:owner_user])

    {:ok, business} =
      Businesses.create_business(user, Enum.into(attrs, %{name: "Test Business"}))

    business
  end

  @doc """
  Creates a job with default attributes; merges `attrs` when given.
  Pass `:business_id` to attach to an existing business (recommended for Twilio tests).
  """
  def job_fixture(attrs \\ %{}) do
    {business_id, attrs} =
      case Map.pop(attrs, :business_id) do
        {nil, attrs} -> {business_fixture().id, attrs}
        {bid, attrs} -> {bid, attrs}
      end

    attrs =
      Enum.into(attrs, %{
        business_id: business_id,
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
