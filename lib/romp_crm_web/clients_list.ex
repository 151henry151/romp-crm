defmodule RompCrmWeb.ClientsList do
  @moduledoc false

  alias RompCrm.Addresses
  alias RompCrm.Clients.Client

  @sort_options [
    {"Alphabetical", :name},
    {"Recently updated", :updated},
    {"Address", :address}
  ]

  def sort_options, do: @sort_options

  def sort_label(:name), do: "Alphabetical"
  def sort_label(:updated), do: "Recently updated"
  def sort_label(:address), do: "Address"

  def prepare_clients(clients, sort_by) when is_list(clients) do
    clients
    |> Enum.sort_by(&sort_key(&1, sort_by))
  end

  defp sort_key(%Client{} = c, :name),
    do: {String.downcase(c.client_name || ""), c.id}

  defp sort_key(%Client{} = c, :updated),
    do: {c.updated_at || c.inserted_at, c.id}

  defp sort_key(%Client{} = c, :address),
    do: {String.downcase(c.address_line1 || c.address || ""), c.client_name || "", c.id}

  def primary_heading(%Client{} = c), do: blank_to_dash(c.client_name)

  def secondary_line(%Client{} = c) do
    addr = Addresses.format_service(c)

    cond do
      addr != "" and (c.phone || "") != "" -> "#{addr} · #{c.phone}"
      addr != "" -> addr
      (c.phone || "") != "" -> c.phone
      (c.client_email || "") != "" -> c.client_email
      true -> nil
    end
  end

  def job_count(%Client{jobs: jobs}) when is_list(jobs), do: length(jobs)
  def job_count(_), do: 0

  defp blank_to_dash(""), do: "—"
  defp blank_to_dash(nil), do: "—"
  defp blank_to_dash(s), do: s
end
