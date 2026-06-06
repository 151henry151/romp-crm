defmodule RompCrmWeb.AddressValues do
  @moduledoc false

  alias RompCrm.Clients.Client
  alias RompCrm.Jobs.Job

  def from_client(%Client{} = client) do
    %{
      "address_line1" => client.address_line1 || "",
      "address_line2" => client.address_line2 || "",
      "city" => client.city || "",
      "state" => client.state || "",
      "postal_code" => client.postal_code || "",
      "billing_address_different" => client.billing_address_different || false,
      "billing_address_line1" => client.billing_address_line1 || "",
      "billing_address_line2" => client.billing_address_line2 || "",
      "billing_city" => client.billing_city || "",
      "billing_state" => client.billing_state || "",
      "billing_postal_code" => client.billing_postal_code || ""
    }
  end

  def from_job(%Job{} = job) do
    %{
      "address_line1" => job.address_line1 || "",
      "address_line2" => job.address_line2 || "",
      "city" => job.city || "",
      "state" => job.state || "",
      "postal_code" => job.postal_code || "",
      "billing_address_different" => job.billing_address_different || false,
      "billing_address_line1" => job.billing_address_line1 || "",
      "billing_address_line2" => job.billing_address_line2 || "",
      "billing_city" => job.billing_city || "",
      "billing_state" => job.billing_state || "",
      "billing_postal_code" => job.billing_postal_code || ""
    }
  end

  def from_form(form, job) do
    base = from_job(job)

    case form.params do
      params when is_map(params) ->
        params
        |> stringify()
        |> Map.merge(base, fn _k, form_val, _job_val -> form_val end)

      _ ->
        base
    end
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
