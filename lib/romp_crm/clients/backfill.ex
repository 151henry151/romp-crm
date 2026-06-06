defmodule RompCrm.Clients.Backfill do
  @moduledoc false

  import Ecto.Query
  alias RompCrm.Repo
  alias RompCrm.Clients.Client
  alias RompCrm.Clients.ClientContact
  alias RompCrm.Jobs.Job

  def run do
    business_ids =
      Repo.all(from j in Job, select: j.business_id, distinct: true, order_by: [asc: j.business_id])

    Enum.each(business_ids, &backfill_business/1)
    :ok
  end

  defp backfill_business(business_id) do
    jobs =
      Repo.all(
        from j in Job,
          where: j.business_id == ^business_id,
          order_by: [asc: j.inserted_at, asc: j.id]
      )

    {_, job_links} =
      Enum.reduce(jobs, {[], %{}}, fn job, {clients_acc, job_links} ->
        contact = ClientContact.from_struct(job)

        if ClientContact.has_identity?(contact) do
          case find_matching_client(clients_acc, contact) do
            %Client{id: id} = client ->
              {clients_acc, Map.put(job_links, job.id, id)}

            nil ->
              attrs = Map.put(contact, :business_id, business_id)

              {:ok, client} =
                %Client{}
                |> Client.changeset(attrs)
                |> Repo.insert()

              {clients_acc ++ [client], Map.put(job_links, job.id, client.id)}
          end
        else
          {clients_acc, job_links}
        end
      end)

    Enum.each(job_links, fn {job_id, client_id} ->
      Repo.update_all(from(j in Job, where: j.id == ^job_id), set: [client_id: client_id])
    end)
  end

  defp find_matching_client(clients, contact) when is_list(clients) do
    Enum.find(clients, fn %Client{} = client ->
      ClientContact.same_client?(ClientContact.from_struct(client), contact)
    end)
  end
end
