defmodule RompCrm.Jobs do
  import Ecto.Query
  alias RompCrm.Repo
  alias RompCrm.Jobs.Job

  def subscribe(business_id) when is_integer(business_id) do
    Phoenix.PubSub.subscribe(RompCrm.PubSub, topic(business_id))
  end

  defp topic(business_id), do: "jobs:business:#{business_id}"

  def list_jobs(business_id) when is_integer(business_id) do
    Repo.all(
      from j in Job,
        where: j.business_id == ^business_id,
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

  def get_job!(id, business_id) when is_integer(business_id) do
    Repo.get_by!(Job, id: id, business_id: business_id)
  end

  def get_job(id, business_id) when is_integer(business_id) do
    Repo.get_by(Job, id: id, business_id: business_id)
  end

  @doc """
  Returns jobs as plain maps suitable for embedding in an SMS-extraction LLM prompt.

  Each row includes integer `"id"` (database primary key). Fields may be `null` when empty.
  """
  def snapshot_for_sms_ai(business_id) when is_integer(business_id) do
    Enum.map(list_jobs(business_id), fn j ->
      %{
        "id" => j.id,
        "client_name" => j.client_name,
        "address" => j.address,
        "phone" => j.phone,
        "work_description" => j.work_description,
        "notes" => j.notes,
        "next_action" => j.next_action,
        "referred_by" => j.referred_by,
        "status" => Atom.to_string(j.status),
        "priority" => Atom.to_string(j.priority)
      }
    end)
  end

  def create_job(attrs) do
    with {:ok, job} <- %Job{} |> Job.changeset(attrs) |> Repo.insert() do
      broadcast(job.business_id, {:created, job})
      {:ok, job}
    end
  end

  def update_job(%Job{} = job, attrs) do
    with {:ok, job} <- job |> Job.changeset(attrs) |> Repo.update() do
      broadcast(job.business_id, {:updated, job})
      {:ok, job}
    end
  end

  def delete_job(%Job{} = job) do
    bid = job.business_id

    with {:ok, job} <- Repo.delete(job) do
      broadcast(bid, {:deleted, job})
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
  def find_job_for_sms_update(match_spec, business_id)
      when is_map(match_spec) and is_integer(business_id) do
    scored =
      list_jobs(business_id)
      |> Enum.map(fn job -> {job, RompCrm.Jobs.SmsMatch.score(job, match_spec)} end)
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
    min = sms_match_min_score()

    cond do
      second == 0 ->
        top >= min

      true ->
        top >= 52 and top >= second + 20
    end
  end

  @doc """
  Returns up to `limit` `{job, score}` pairs for SMS match scoring (highest scores first).
  Used to word clarification texts when matching is ambiguous.
  """
  def top_match_candidates(match_spec, business_id, limit \\ 3)
      when is_map(match_spec) and is_integer(business_id) and is_integer(limit) do
    scored =
      list_jobs(business_id)
      |> Enum.map(fn job -> {job, RompCrm.Jobs.SmsMatch.score(job, match_spec)} end)
      |> Enum.sort_by(fn {_, sc} -> -sc end)
      |> Enum.take(limit)

    scored
  end

  @doc """
  Short SMS asking which job the user meant when heuristic matching ties.

  Uses the top two scored jobs from `match_spec`.
  """
  def ambiguous_match_clarification_sms(match_spec, business_id) when is_map(match_spec) do
    case top_match_candidates(match_spec, business_id, 3) do
      [{j1, _}, {j2, _} | _] ->
        n1 = job_label(j1)
        n2 = job_label(j2)

        "Which one—#{n1} or #{n2}? Reply with that client name."

      _ ->
        "Multiple jobs match—which client did you mean? Be specific."
    end
  end

  defp job_label(%Job{} = j) do
    cn = j.client_name || "Unknown"

    wd =
      case j.work_description do
        nil -> ""
        "" -> ""
        w -> String.slice(String.trim(w), 0, 44)
      end

    if wd != "", do: "#{cn} (#{wd})", else: cn
  end

  defp broadcast(business_id, message) do
    Phoenix.PubSub.broadcast(RompCrm.PubSub, topic(business_id), message)
  end
end
