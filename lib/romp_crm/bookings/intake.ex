defmodule RompCrm.Bookings.Intake do
  @moduledoc """
  Customer intake during SMS self-scheduling: what we still need from the
  client (work description, service/billing address, email) and applying their
  replies onto the linked job (and client record).
  """

  require Logger

  alias RompCrm.Addresses
  alias RompCrm.Bookings
  alias RompCrm.Bookings.BookingLink
  alias RompCrm.Clients
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo

  @doc """
  Snapshot for the customer-booking AI: on-file values and which fields still
  need collection or confirmation.
  """
  def snapshot_for_link(%BookingLink{} = link) do
    link = Repo.preload(link, [:client, :job])
    job = link.job || blank_job_record(link)
    client = link.client

    service_address = format_service(job, client)
    email = present(job.client_email) || present(client && client.client_email)
    comments = present(job.customer_comments)
    billing_confirmed = Bookings.intake_flag?(link, "billing_confirmed")

    needs_billing =
      service_address != nil and not billing_confirmed and
        not (job.billing_address_different && billing_address_present?(job))

    needs = %{
      "customer_comments" => comments == nil,
      "service_address" => service_address == nil,
      "email" => email == nil,
      "billing_address" => needs_billing,
      "any" =>
        comments == nil or service_address == nil or email == nil or needs_billing
    }

    %{
      "job_id" => link.job_id,
      "on_file" => %{
        "customer_comments" => comments,
        "service_address" => service_address,
        "email" => email,
        "billing_address_different" => job.billing_address_different,
        "billing_address" =>
          if(job.billing_address_different,
            do: blank_to_nil(Addresses.format_billing(job)),
            else: nil
          )
      },
      "needs" => needs
    }
  end

  @doc """
  Applies customer-provided intake fields to the job behind **`link`**, creating
  that job when missing. Syncs contact fields to the linked client when present.
  Returns `{:ok, updated_link, updated_job}` or `{:error, changeset}`.
  """
  def apply_updates(%BookingLink{} = link, updates) when is_map(updates) do
    updates = stringify_keys(updates)

    with {:ok, link, job} <- ensure_job(link),
         {:ok, job} <- patch_job(job, updates),
         :ok <- sync_client_from_job(job, link),
         {:ok, link} <- maybe_mark_billing_confirmed(link, updates) do
      {:ok, link, Jobs.get_job!(job.id, link.business_id)}
    end
  end

  defp ensure_job(%BookingLink{job_id: id} = link) when is_integer(id) do
    job = Jobs.get_job!(id, link.business_id)
    {:ok, link, job}
  end

  defp ensure_job(%BookingLink{} = link) do
    link = Repo.preload(link, :client)

    attrs = %{
      business_id: link.business_id,
      client_id: link.client_id,
      client_name: (link.client && link.client.client_name) || "",
      phone: link.client && link.client.phone,
      work_description: link.job_type_label,
      status: :lead
    }

    with {:ok, %Job{} = job} <- Jobs.create_job(attrs),
         {:ok, link} <-
           link
           |> BookingLink.changeset(%{job_id: job.id})
           |> Repo.update() do
      {:ok, link, job}
    end
  end

  defp patch_job(%Job{} = job, updates) do
    attrs =
      updates
      |> Map.take([
        "customer_comments",
        "client_email",
        "address",
        "address_line1",
        "address_line2",
        "city",
        "state",
        "postal_code",
        "billing_address_different",
        "billing_address",
        "billing_address_line1",
        "billing_address_line2",
        "billing_city",
        "billing_state",
        "billing_postal_code"
      ])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or (is_binary(v) and String.trim(v) == "") end)
      |> Map.new()

    attrs =
      attrs
      |> Addresses.merge_ai_address_attrs()
      |> enrich_billing_attrs(updates)

    if attrs == %{} do
      {:ok, job}
    else
      Jobs.update_job(job, atomize_job_attrs(attrs))
    end
  end

  defp enrich_billing_attrs(attrs, updates) do
    cond do
      truthy?(Map.get(updates, "billing_same_as_service")) ->
        attrs
        |> Map.put("billing_address_different", false)
        |> Map.drop([
          "billing_address",
          "billing_address_line1",
          "billing_address_line2",
          "billing_city",
          "billing_state",
          "billing_postal_code"
        ])

      truthy?(Map.get(updates, "billing_address_different")) ->
        billing =
          updates
          |> Map.take([
            "billing_address",
            "billing_address_line1",
            "billing_address_line2",
            "billing_city",
            "billing_state",
            "billing_postal_code"
          ])
          |> Addresses.merge_ai_address_attrs()
          |> Map.put("billing_address_different", true)

        Map.merge(attrs, billing)

      true ->
        attrs
    end
  end

  defp sync_client_from_job(%Job{client_id: client_id} = job, _link) when is_integer(client_id) do
    case Clients.get_client(client_id, job.business_id) do
      nil ->
        :ok

      client ->
        contact_attrs =
          job
          |> Clients.contact_attrs_from_job()
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        case Clients.update_client(client, contact_attrs) do
          {:ok, _} -> :ok
          {:error, cs} -> Logger.warning("Intake client sync failed: #{inspect(cs.errors)}")
        end
    end
  end

  defp sync_client_from_job(_job, _link), do: :ok

  defp maybe_mark_billing_confirmed(link, updates) do
    if truthy?(Map.get(updates, "billing_same_as_service")) or
         truthy?(Map.get(updates, "billing_address_different")) do
      Bookings.mark_intake_flag(link, "billing_confirmed", true)
    else
      {:ok, link}
    end
  end

  defp atomize_job_attrs(attrs) do
    Enum.map(attrs, fn {k, v} -> {String.to_existing_atom(k), v} end) |> Map.new()
  rescue
    ArgumentError ->
      Enum.map(attrs, fn {k, v} -> {String.to_atom(k), v} end) |> Map.new()
  end

  defp format_service(%Job{} = job, client) do
    job_addr = blank_to_nil(Addresses.format_service(job))
    client_addr = if(client, do: blank_to_nil(Addresses.format_service(client)), else: nil)
    job_addr || client_addr
  end

  defp billing_address_present?(%Job{} = job) do
    blank_to_nil(Addresses.format_billing(job)) != nil
  end

  defp blank_job_record(%BookingLink{} = link) do
    %Job{
      business_id: link.business_id,
      client_id: link.client_id,
      billing_address_different: false
    }
  end

  defp present(nil), do: nil
  defp present(""), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(value), do: to_string(value)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      "—" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp truthy?(v) when v in [true, "true", "1", 1, "on", "yes"], do: true
  defp truthy?(_), do: false
end
