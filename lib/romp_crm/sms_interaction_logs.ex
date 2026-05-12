defmodule RompCrm.SmsInteractionLogs do
  @moduledoc """
  Persists one row per inbound SMS handled by **`TwilioWebhookController`** (with reply and
  structured summaries) for data-export CSVs.
  """

  import Ecto.Query

  alias RompCrm.Repo
  alias RompCrm.SmsInteractionLogs.Log

  def insert(attrs) when is_map(attrs) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  def list_for_business_ids(business_ids, opts \\ []) when is_list(business_ids) do
    limit = Keyword.get(opts, :limit, 20_000)

    if business_ids == [] do
      []
    else
      Repo.all(
        from l in Log,
          where: l.business_id in ^business_ids,
          order_by: [asc: l.id],
          limit: ^limit
      )
    end
  end
end
