defmodule RompCrm.Bookings.Escalations do
  @moduledoc """
  Client questions the scheduling agent cannot answer: escalate to the
  contractor, relay answers back, and optionally store per-business memories.
  """

  import Ecto.Query

  alias RompCrm.Bookings.{Escalation, SchedulingMemory}
  alias RompCrm.Repo

  @open_statuses ~w(pending_contractor pending_memory_confirm)

  def create_escalation(attrs) when is_map(attrs) do
    %Escalation{}
    |> Escalation.changeset(attrs)
    |> Repo.insert()
  end

  def get_escalation!(id), do: Repo.get!(Escalation, id)

  def get_escalation(id, business_id) when is_integer(id) and is_integer(business_id) do
    Repo.one(
      from e in Escalation,
        where: e.id == ^id and e.business_id == ^business_id
    )
  end

  def update_escalation(%Escalation{} = escalation, attrs) when is_map(attrs) do
    escalation
    |> Escalation.changeset(attrs)
    |> Repo.update()
  end

  def open_for_business?(business_id) when is_integer(business_id) do
    Repo.exists?(
      from e in Escalation,
        where: e.business_id == ^business_id and e.status in ^@open_statuses
    )
  end

  def list_open_for_business(business_id) when is_integer(business_id) do
    Repo.all(
      from e in Escalation,
        where: e.business_id == ^business_id and e.status in ^@open_statuses,
        order_by: [asc: e.id]
    )
  end

  def list_memories_for_business(business_id) when is_integer(business_id) do
    Repo.all(
      from m in SchedulingMemory,
        where: m.business_id == ^business_id,
        order_by: [desc: m.id],
        limit: 50
    )
  end

  def memories_snapshot_for_ai(business_id) when is_integer(business_id) do
    business_id
    |> list_memories_for_business()
    |> Enum.map(fn m ->
      %{
        "id" => m.id,
        "topic" => m.topic,
        "answer" => m.answer_text
      }
    end)
  end

  def create_memory(attrs) when is_map(attrs) do
    %SchedulingMemory{}
    |> SchedulingMemory.changeset(attrs)
    |> Repo.insert()
  end

  def mark_resolved(%Escalation{} = escalation, attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    escalation
    |> Escalation.changeset(
      Map.merge(attrs, %{
        status: "resolved",
        resolved_at: now
      })
    )
    |> Repo.update()
  end

  def mark_contractor_handling(%Escalation{} = escalation) do
    escalation
    |> Escalation.changeset(%{status: "contractor_handling", resolved_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end
end
