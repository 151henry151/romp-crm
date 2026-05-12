defmodule RompCrm.BusinessAuditLogs do
  @moduledoc """
  Append-only audit rows for business-scoped data changes (web UI and SMS).

  Inserts must never break the caller; failures are logged only.
  """

  import Ecto.Query

  require Logger

  alias RompCrm.BusinessAuditLogs.Log
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
end
