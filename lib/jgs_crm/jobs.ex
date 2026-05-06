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
          asc:
            fragment(
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

  @doc """
  Picks at most one existing job that best matches SMS `match` clues (from Claude).

  Returns `{:ok, job}`, `{:error, :no_match}`, or `{:error, :ambiguous}` when two jobs score too close.
  """
  def find_job_for_sms_update(match_spec) when is_map(match_spec) do
    scored =
      list_jobs()
      |> Enum.map(fn job -> {job, JgsCrm.Jobs.SmsMatch.score(job, match_spec)} end)
      |> Enum.filter(fn {_, sc} -> sc >= sms_match_min_score() end)
      |> Enum.sort_by(fn {_, sc} -> -sc end)

    case scored do
      [] ->
        {:error, :no_match}

      [{job, top} | rest] ->
        second =
          case rest do
            [{_, s} | _] -> s
            [] -> 0
          end

        if sms_unique_winner?(top, second), do: {:ok, job}, else: {:error, :ambiguous}
    end
  end

  defp sms_match_min_score, do: 38

  defp sms_unique_winner?(top, second) do
    top >= 52 and (second == 0 or top >= second + 20)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(JgsCrm.PubSub, @topic, message)
  end
end
