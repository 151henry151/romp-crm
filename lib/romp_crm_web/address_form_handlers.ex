defmodule RompCrmWeb.AddressFormHandlers do
  @moduledoc false

  alias RompCrm.{Addresses, GoogleMaps}

  @service_keys ~w(address_line1 address_line2 city state postal_code)
  @billing_keys ~w(billing_address_line1 billing_address_line2 billing_city billing_state billing_postal_code)

  @doc """
  Geocode typed address parts. Returns a suggestion map for the UI, or `nil` when
  no choice prompt is needed (same address, empty, API off, or geocode miss).
  """
  def build_suggestion(%{"part" => part} = params) when part in ["service", "billing"] do
    typed_parts = typed_parts(params, part)
    typed_formatted = Addresses.format_parts(typed_parts)

    if typed_formatted == "" do
      nil
    else
      case GoogleMaps.geocode_service(typed_parts) do
        {:ok, suggested} ->
          suggested_formatted = suggested["formatted"] || Addresses.format_parts(suggested)

          if Addresses.same_address?(typed_parts, suggested) do
            nil
          else
            %{
              "part" => part,
              "typed_formatted" => typed_formatted,
              "suggested_formatted" => suggested_formatted,
              "typed" => form_fields(params, part),
              "suggested" => form_fields_from_geocode(suggested, part)
            }
          end

        _ ->
          nil
      end
    end
  end

  def build_suggestion(_), do: nil

  @doc "Merge chosen address fields into nested job form params (`%{\"job\" => ...}`)."
  def merge_fill_into_job_params(%{"job" => job_params} = params, fill, _part)
      when is_map(job_params) and is_map(fill) do
    %{params | "job" => Map.merge(job_params, fill)}
  end

  def merge_fill_into_job_params(params, fill, _part) when is_map(params) and is_map(fill) do
    Map.merge(params, fill)
  end

  def merge_fill_into_job_params(params, _fill, _part), do: params

  @doc "Extract address attrs from inline expanded-row `%{\"job\" => ...}` params."
  def job_address_attrs_from_params(%{"job" => job_params}) when is_map(job_params) do
    job_params
    |> Addresses.merge_ai_address_attrs()
    |> Map.take(
      @service_keys ++
        ["billing_address_different"] ++ @billing_keys
    )
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def job_address_attrs_from_params(_), do: %{}

  defp typed_parts(params, "billing") do
    %{
      "address_line1" => params["billing_address_line1"],
      "address_line2" => params["billing_address_line2"],
      "city" => params["billing_city"],
      "state" => params["billing_state"],
      "postal_code" => params["billing_postal_code"]
    }
  end

  defp typed_parts(params, "service") do
    Map.take(params, @service_keys)
  end

  defp form_fields(params, "billing") do
    Map.take(params, @billing_keys)
  end

  defp form_fields(params, "service") do
    Map.take(params, @service_keys)
  end

  defp form_fields_from_geocode(suggested, "billing") do
    %{
      "billing_address_line1" => suggested["address_line1"],
      "billing_address_line2" => suggested["address_line2"],
      "billing_city" => suggested["city"],
      "billing_state" => suggested["state"],
      "billing_postal_code" => suggested["postal_code"]
    }
  end

  defp form_fields_from_geocode(suggested, "service") do
    Map.take(suggested, @service_keys)
  end
end
