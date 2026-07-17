defmodule RompCrm.Clients do
  @moduledoc """
  Clients (contacts) per business workspace — persistent records separate from jobs.
  """

  import Ecto.Query
  alias RompCrm.Repo
  alias RompCrm.Clients.Client
  alias RompCrm.Clients.ClientContact
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job

  def subscribe(business_id) when is_integer(business_id) do
    Phoenix.PubSub.subscribe(RompCrm.PubSub, topic(business_id))
  end

  defp topic(business_id), do: "clients:business:#{business_id}"

  defp broadcast(business_id, msg) do
    Phoenix.PubSub.broadcast(RompCrm.PubSub, topic(business_id), msg)
  end

  def list_clients(business_id) when is_integer(business_id) do
    Repo.all(
      from c in Client,
        where: c.business_id == ^business_id,
        order_by: [asc: c.client_name, asc: c.id],
        preload: [jobs: ^jobs_for_client_preload()]
    )
  end

  defp jobs_for_client_preload do
    from j in Job,
      order_by: [
        asc:
          fragment(
            "CASE ? WHEN 'in_progress' THEN 0 WHEN 'pending' THEN 1 WHEN 'lead' THEN 2 ELSE 3 END",
            j.status
          ),
        desc: j.inserted_at
      ]
  end

  def get_client!(id, business_id) when is_integer(id) and is_integer(business_id) do
    Repo.one!(
      from c in Client,
        where: c.id == ^id and c.business_id == ^business_id,
        preload: [jobs: ^jobs_for_client_preload()]
    )
  end

  def get_client(id, business_id) when is_integer(id) and is_integer(business_id) do
    Repo.one(
      from c in Client,
        where: c.id == ^id and c.business_id == ^business_id,
        preload: [jobs: ^jobs_for_client_preload()]
    )
  end

  def change_client(%Client{} = client, attrs \\ %{}) do
    Client.changeset(client, attrs)
  end

  def create_client(attrs) when is_map(attrs) do
    case %Client{} |> Client.changeset(attrs) |> Repo.insert() do
      {:ok, client} ->
        client = Repo.preload(client, [jobs: jobs_for_client_preload()], force: true)
        broadcast(client.business_id, {:created, client})
        {:ok, client}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_client(%Client{} = client, attrs) when is_map(attrs) do
    case client |> Client.changeset(attrs) |> Repo.update() do
      {:ok, client} ->
        client = Repo.preload(client, [jobs: jobs_for_client_preload()], force: true)
        broadcast(client.business_id, {:updated, client})
        {:ok, client}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates client contact fields and copies them onto every linked job row.
  """
  def update_client_and_sync_jobs(%Client{} = client, attrs) when is_map(attrs) do
    with {:ok, client} <- update_client(client, attrs),
         :ok <- sync_linked_jobs_from_client(client) do
      {:ok, client}
    end
  end

  @doc """
  Applies a job update patch. Contact fields (phone, name, address, …) on a linked
  job are written to the **client** and synced onto all linked jobs so
  `merge_client_onto_job/1` does not blank them on the next read.
  Non-contact fields are applied to this job only.
  """
  def update_job_contact_and_sync(%Job{} = job, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    contact_keys = Enum.map(ClientContact.contact_fields(), &Atom.to_string/1)
    contact_attrs = Map.take(attrs, contact_keys)
    other_attrs = Map.drop(attrs, contact_keys)

    cond do
      is_integer(job.client_id) and contact_attrs != %{} ->
        case get_client(job.client_id, job.business_id) do
          nil ->
            Jobs.update_job(job, attrs)

          client ->
            with {:ok, _client} <- update_client_and_sync_jobs(client, contact_attrs) do
              job = Jobs.get_job!(job.id, job.business_id)

              if other_attrs == %{} do
                {:ok, job}
              else
                Jobs.update_job(job, other_attrs)
              end
            end
        end

      true ->
        Jobs.update_job(job, attrs)
    end
  end

  defp sync_linked_jobs_from_client(%Client{} = client) do
    job_attrs =
      client
      |> copy_client_contact_to_job_attrs()
      |> Map.put("client_id", client.id)

    client = Repo.preload(client, :jobs, force: true)

    Enum.each(client.jobs || [], fn job ->
      {:ok, _} = Jobs.update_job(job, job_attrs)
    end)

    :ok
  end

  @doc """
  Creates a client from contact attrs and links **`job`** (updates job contact + client_id).
  """
  def create_client_from_contact_and_link_job(%Job{} = job, contact_attrs) when is_map(contact_attrs) do
    attrs =
      contact_attrs
      |> Map.new(fn {k, v} -> {if(is_atom(k), do: k, else: String.to_atom(to_string(k))), v} end)
      |> Map.put(:business_id, job.business_id)

    with {:ok, client} <- create_client(attrs),
         {:ok, job} <- link_job_to_client(job, client) do
      {:ok, client, job}
    end
  end

  def client_contact_job_field?(field) when is_binary(field) do
    field in ~w(client_name phone client_email address)
  end

  def client_contact_job_field?(_), do: false

  @doc """
  Deletes **`client`** and every linked job (photos, hours, etc. via `Jobs.delete_job/1`).
  """
  def delete_client_and_jobs(%Client{} = client) do
    bid = client.business_id
    client = get_client!(client.id, bid)

    Repo.transact(fn ->
      Enum.each(client.jobs || [], fn job ->
        {:ok, _} = Jobs.delete_job(job)
      end)

      case Repo.delete(client) do
        {:ok, deleted} ->
          broadcast(bid, {:deleted, deleted})
          {:ok, deleted}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def count_linked_jobs(%Client{id: id}) do
    Repo.one(from j in Job, where: j.client_id == ^id, select: count(j.id)) || 0
  end

  @doc """
  JSON snapshot for SMS / chat AI (per business).
  """
  def snapshot_for_sms_ai(business_id) when is_integer(business_id) do
    clients =
      Repo.all(
        from c in Client,
          where: c.business_id == ^business_id,
          order_by: [asc: c.client_name, asc: c.id]
      )

    Enum.map(clients, &client_snapshot_row/1)
  end

  defp client_snapshot_row(%Client{} = c) do
    %{
      id: c.id,
      client_name: c.client_name,
      phone: c.phone,
      client_email: c.client_email,
      address: c.address,
      address_line1: c.address_line1,
      address_line2: c.address_line2,
      city: c.city,
      state: c.state,
      postal_code: c.postal_code,
      billing_address_different: c.billing_address_different,
      billing_address_line1: c.billing_address_line1,
      billing_address_line2: c.billing_address_line2,
      billing_city: c.billing_city,
      billing_state: c.billing_state,
      billing_postal_code: c.billing_postal_code,
      notes: c.notes
    }
  end

  @doc """
  Overlays linked client contact fields onto a job for list/display (job-specific fields unchanged).
  """
  def merge_client_onto_job(%Job{client: %Client{} = client} = job) do
    contact = ClientContact.from_struct(client)

    Enum.reduce(ClientContact.contact_fields(), job, fn field, acc ->
      Map.put(acc, field, Map.get(contact, field))
    end)
  end

  def merge_client_onto_job(%Job{} = job), do: job

  def contact_attrs_from_job(%Job{} = job) do
    job |> ClientContact.from_struct() |> Map.put(:business_id, job.business_id)
  end

  def copy_client_contact_to_job_attrs(%Client{} = client) do
    client |> ClientContact.from_struct() |> ClientContact.to_job_attrs()
  end

  def link_job_to_client(%Job{} = job, %Client{} = client) do
    attrs =
      client
      |> ClientContact.from_struct()
      |> ClientContact.to_job_attrs()
      |> Map.put("client_id", client.id)

    Jobs.update_job(job, attrs)
  end

  @doc """
  After a job row exists, link it to an existing client (by **`client_id`** in **`attrs`**)
  or create a new client when contact identity is present.
  """
  def finalize_job_client_link(%Job{} = job, attrs) when is_map(attrs) do
    client_id =
      case Map.get(attrs, "client_id") || Map.get(attrs, :client_id) do
        id when is_integer(id) -> id
        id when is_binary(id) ->
          case Integer.parse(String.trim(id)) do
            {n, _} -> n
            :error -> nil
          end

        _ ->
          nil
      end

    cond do
      client_id ->
        case get_client(client_id, job.business_id) do
          nil -> {:ok, job}
          client -> link_job_to_client(job, client)
        end

      ClientContact.has_identity?(attrs) ->
        case create_client_from_contact_and_link_job(job, ClientContact.from_map(attrs)) do
          {:ok, _client, linked} -> {:ok, linked}
          other -> other
        end

      true ->
        {:ok, job}
    end
  end

  def find_same_clients(business_id, contact) when is_integer(business_id) and is_map(contact) do
    Repo.all(from c in Client, where: c.business_id == ^business_id)
    |> Enum.filter(fn %Client{} = client ->
      ClientContact.same_client?(ClientContact.from_struct(client), contact)
    end)
  end
end
