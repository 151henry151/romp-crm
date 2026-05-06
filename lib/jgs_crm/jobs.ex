defmodule JgsCrm.Jobs do
  import Ecto.Query
  alias JgsCrm.Repo
  alias JgsCrm.Jobs.Job

  @topic "jobs"

  def subscribe do
    Phoenix.PubSub.subscribe(JgsCrm.PubSub, @topic)
  end

  def list_jobs do
    Repo.all(
      from j in Job,
        order_by: [
          asc: fragment("CASE ? WHEN 'high' THEN 0 ELSE 1 END", j.priority),
          asc: fragment(
            "CASE ? WHEN 'in_progress' THEN 0 WHEN 'pending' THEN 1 WHEN 'lead' THEN 2 ELSE 3 END",
            j.status
          ),
          asc: j.client_name
        ]
    )
  end

  def get_job!(id), do: Repo.get!(Job, id)

  def create_job(attrs) do
    with {:ok, job} <- %Job{} |> Job.changeset(attrs) |> Repo.insert() do
      broadcast({:created, job})
      {:ok, job}
    end
  end

  def update_job(%Job{} = job, attrs) do
    with {:ok, job} <- job |> Job.changeset(attrs) |> Repo.update() do
      broadcast({:updated, job})
      {:ok, job}
    end
  end

  def delete_job(%Job{} = job) do
    with {:ok, job} <- Repo.delete(job) do
      broadcast({:deleted, job})
      {:ok, job}
    end
  end

  def change_job(%Job{} = job, attrs \\ %{}) do
    Job.changeset(job, attrs)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(JgsCrm.PubSub, @topic, message)
  end
end
