defmodule RompCrm.BusinessAuditLogs do
  @moduledoc """
  Append-only audit rows for business-scoped data changes (web UI and SMS).

  Inserts must never break the caller; failures are logged only.
  """

  import Ecto.Query

  require Logger

  alias RompCrm.BusinessAuditLogs.Log
  alias RompCrm.BusinessAuditLogs.Detail
  alias RompCrm.Repo

  @doc """
  Inserts one audit row. **`attrs`** may include **`metadata`** as a map (encoded as JSON) or string.

  Returns **`{:ok, log}`** or **`{:error, changeset}`**; use **`record!/1`** when the result should be ignored.
  """
  def insert(attrs) when is_map(attrs) do
    attrs = normalize_metadata(attrs)

    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Same as **`insert/1`** but returns **`:ok`** or **`:error`** and never raises from audit failures.
  """
  def record(attrs) when is_map(attrs) do
    attrs = enrich_metadata_attrs(attrs)

    case insert(attrs) do
      {:ok, _} ->
        :ok

      {:error, cs} ->
        Logger.warning(
          "BusinessAuditLogs: insert failed business_id=#{inspect(attrs[:business_id])} errors=#{inspect(cs.errors)}"
        )

        :error
    end
  end

  defp normalize_metadata(%{metadata: meta} = attrs) when is_map(meta) do
    %{attrs | metadata: Jason.encode!(meta)}
  end

  defp normalize_metadata(attrs), do: attrs

  defp enrich_metadata_attrs(%{metadata: meta} = attrs) when is_map(meta) do
    enriched =
      Detail.enrich(meta,
        changes: Map.get(meta, :changes, []),
        sms_inbound: Map.get(meta, :sms_inbound),
        sms_outbound: Map.get(meta, :sms_outbound),
        summary: Map.get(meta, :summary)
      )

    %{attrs | metadata: enriched}
  end

  defp enrich_metadata_attrs(attrs), do: attrs

  def list_for_business_ids(business_ids, opts \\ []) when is_list(business_ids) do
    limit = Keyword.get(opts, :limit, 50_000)

    if business_ids == [] do
      []
    else
      Repo.all(
        from l in Log,
          where: l.business_id in ^business_ids,
          order_by: [asc: l.id],
          limit: ^limit,
          preload: [:actor_user]
      )
    end
  end

  @doc """
  Recent job deletions for AI context: `[%{job_id, client_name, deleted_at}, ...]` newest first.

  Sourced from **`jobs.delete`** audit rows. Lets the agent know a job mentioned in chat
  was removed from the workspace even when **`prior_turns`** still reference it.
  """
  def recent_deleted_jobs_snapshot(business_id, opts \\ []) when is_integer(business_id) do
    limit = Keyword.get(opts, :limit, 30)
    within_days = Keyword.get(opts, :within_days, 60)

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-within_days * 86_400, :second)
      |> DateTime.truncate(:second)

    from(l in Log,
      where: l.business_id == ^business_id,
      where: l.action == "jobs.delete",
      where: l.entity_type == "jobs",
      where: l.inserted_at >= ^cutoff,
      order_by: [desc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&deleted_job_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp deleted_job_row(%Log{} = log) do
    meta = Detail.decode_metadata(log.metadata)
    client_name = deleted_job_client_name(meta, log)
    job_id = log.entity_id || meta["job_id"] || meta[:job_id]

    if is_integer(job_id) do
      %{
        "job_id" => job_id,
        "client_name" => client_name || "",
        "deleted_at" => DateTime.to_iso8601(log.inserted_at)
      }
    end
  end

  defp deleted_job_client_name(meta, %Log{} = log) when is_map(meta) do
    cond do
      name = meta["client_name"] || meta[:client_name] ->
        to_string(name)

      true ->
        (meta["changes"] || meta[:changes] || [])
        |> List.wrap()
        |> Enum.find_value(fn
          %{"type" => "job_deleted"} = c -> c["client_name"] || c[:client_name]
          %{type: "job_deleted"} = c -> Map.get(c, :client_name) || Map.get(c, "client_name")
          _ -> nil
        end)
        |> case do
          nil -> fallback_client_name_from_entity(log)
          name -> to_string(name)
        end
    end
  end

  defp fallback_client_name_from_entity(_log), do: nil
end
