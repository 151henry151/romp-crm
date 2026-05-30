defmodule RompCrm.GoogleMaps do
  @moduledoc """
  Google Geocoding API client for address validation suggestions.
  """

  @geocode_url "https://maps.googleapis.com/maps/api/geocode/json"

  def configured? do
    api_key() not in [nil, ""]
  end

  def api_key, do: Application.get_env(:romp_crm, :google_maps_api_key)

  @doc """
  Geocode a structured address. Returns normalized components and a formatted line.
  """
  def geocode_service(%{} = parts) do
    if configured?() do
      query = RompCrm.Addresses.format_parts(parts)

      if query == "" do
        {:error, :empty}
      else
        request_geocode(query)
      end
    else
      {:error, :not_configured}
    end
  end

  defp request_geocode(query) do
    url = "#{@geocode_url}?#{URI.encode_query(address: query, key: api_key())}"

    case Finch.build(:get, url) |> Finch.request(RompCrm.Finch) do
      {:ok, %{status: 200, body: body}} ->
        decode_geocode_response(body)

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_geocode_response(body) do
    with {:ok, %{"status" => "OK", "results" => [top | _]}} <- Jason.decode(body) do
      {:ok, parse_result(top)}
    else
      {:ok, %{"status" => status}} -> {:error, {:google, status}}
      _ -> {:error, :invalid_response}
    end
  end

  defp parse_result(%{"formatted_address" => formatted, "address_components" => components}) do
    parts = components_to_parts(components)

    {:ok,
     %{
       "address_line1" => street_line(parts),
       "address_line2" => parts.subpremise,
       "city" => parts.city,
       "state" => parts.state,
       "postal_code" => parts.postal_code,
       "formatted" => formatted
     }}
  end

  defp components_to_parts(components) when is_list(components) do
    Enum.reduce(components, %{street_number: nil, route: nil, subpremise: nil, city: nil, state: nil, postal_code: nil}, fn
      %{"long_name" => name, "types" => types}, acc ->
        cond do
          "street_number" in types -> %{acc | street_number: name}
          "route" in types -> %{acc | route: name}
          "subpremise" in types -> %{acc | subpremise: name}
          "locality" in types -> %{acc | city: name}
          "administrative_area_level_1" in types -> %{acc | state: name}
          "postal_code" in types -> %{acc | postal_code: name}
          true -> acc
        end
    end)
  end

  defp street_line(%{street_number: n, route: r}) do
    [n, r]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      line -> line
    end
  end
end
