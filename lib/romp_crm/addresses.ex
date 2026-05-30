defmodule RompCrm.Addresses do
  @moduledoc """
  Structured service and billing address helpers for jobs.
  """

  @service_fields ~w(address_line1 address_line2 city state postal_code)a
  @billing_fields ~w(billing_address_line1 billing_address_line2 billing_city billing_state billing_postal_code)a

  @type address_map :: %{
          optional(String.t()) => String.t() | nil
        }

  def service_fields, do: @service_fields
  def billing_fields, do: @billing_fields

  @doc "Display string for service/site address (falls back to legacy `address`)."
  def format_service(%_{} = record) do
    formatted =
      record
      |> Map.take(@service_fields)
      |> format_parts()

    case formatted do
      "" -> blank_to_nil(Map.get(record, :address)) || "—"
      other -> other
    end
  end

  def format_service(map) when is_map(map), do: format_service(struct(RompCrm.Jobs.Job, Map.new(map)))

  @doc "Display string for billing address when different from service."
  def format_billing(%_{billing_address_different: true} = record) do
    record
    |> Map.take(@billing_fields)
    |> Map.new(fn {k, v} -> {String.replace_prefix(to_string(k), "billing_", ""), v} end)
    |> format_parts()
    |> case do
      "" -> "—"
      other -> other
    end
  end

  def format_billing(_), do: nil

  def service_display_lines(%_{} = record) do
    base = format_service(record)

    if record.billing_address_different do
      billing = format_billing(record)

      if is_binary(billing) and billing != "" and billing != "—" do
        [base, "Billing: #{billing}"]
      else
        [base]
      end
    else
      [base]
    end
  end

  @doc "Merge AI / legacy flat `address` into structured service attrs."
  def merge_ai_address_attrs(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    structured_present? =
      Enum.any?(@service_fields, fn field ->
        val = Map.get(attrs, to_string(field))
        is_binary(val) and String.trim(val) != ""
      end)

    attrs =
      if structured_present? do
        attrs
      else
        case blank_to_nil(Map.get(attrs, "address")) do
          nil -> attrs
          flat -> Map.merge(attrs, from_legacy_string(flat))
        end
      end

    billing_requested? =
      truthy?(Map.get(attrs, "billing_address_different")) or
        not is_nil(blank_to_nil(Map.get(attrs, "billing_address"))) or
        Enum.any?(@billing_fields, fn field ->
          val = Map.get(attrs, to_string(field))
          is_binary(val) and String.trim(val) != ""
        end)

    attrs =
      if billing_requested? do
        attrs
        |> Map.put("billing_address_different", true)
        |> merge_billing_from_ai()
      else
        attrs
      end

    attrs
  end

  def merge_ai_address_attrs(other), do: other

  defp merge_billing_from_ai(attrs) do
    billing_structured? =
      Enum.any?(@billing_fields, fn field ->
        val = Map.get(attrs, to_string(field))
        is_binary(val) and String.trim(val) != ""
      end)

    if billing_structured? do
      Map.put(attrs, "billing_address_different", true)
    else
      case blank_to_nil(Map.get(attrs, "billing_address")) do
        nil ->
          Map.put(attrs, "billing_address_different", true)

        flat ->
          flat_attrs = from_legacy_string(flat)

          attrs
          |> Map.put("billing_address_different", true)
          |> Map.put("billing_address_line1", Map.get(flat_attrs, "address_line1"))
          |> Map.put("billing_address_line2", Map.get(flat_attrs, "address_line2"))
          |> Map.put("billing_city", Map.get(flat_attrs, "city"))
          |> Map.put("billing_state", Map.get(flat_attrs, "state"))
          |> Map.put("billing_postal_code", Map.get(flat_attrs, "postal_code"))
      end
    end
  end

  def from_legacy_string(address) when is_binary(address) do
    trimmed = String.trim(address)

    if trimmed == "" do
      %{}
    else
      %{"address_line1" => trimmed}
    end
  end

  def from_legacy_string(_), do: %{}

  def service_attrs_from_form(params) when is_map(params) do
    params
    |> stringify_keys()
    |> Map.take(Enum.map(@service_fields, &to_string/1))
  end

  def billing_attrs_from_form(params) when is_map(params) do
    params
    |> stringify_keys()
    |> Map.take(Enum.map(@billing_fields, &to_string/1))
    |> Map.put("billing_address_different", truthy?(Map.get(params, "billing_address_different")))
  end

  def format_parts(%{} = parts) do
    line1 = blank_to_nil(parts["address_line1"] || parts[:address_line1])
    line2 = blank_to_nil(parts["address_line2"] || parts[:address_line2])
    city = blank_to_nil(parts["city"] || parts[:city])
    state = blank_to_nil(parts["state"] || parts[:state])
    postal = blank_to_nil(parts["postal_code"] || parts[:postal_code])

    city_state_zip =
      [city, state]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")
      |> case do
        "" -> postal
        cs when is_binary(postal) -> cs <> " " <> postal
        cs -> cs
      end

    [line1, line2, city_state_zip]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  def atom_job_address_attrs(map) when is_map(map) do
    map
    |> merge_ai_address_attrs()
    |> Map.take([
      "address_line1",
      "address_line2",
      "city",
      "state",
      "postal_code",
      "billing_address_different",
      "billing_address_line1",
      "billing_address_line2",
      "billing_city",
      "billing_state",
      "billing_postal_code"
    ])
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Map.new()
  end

  @doc "Like `atom_job_address_attrs/1` but only when the raw map mentions an address field (for SMS patches)."
  def atom_job_address_attrs_if_present(map) when is_map(map) do
    if address_key_present?(map) do
      map
      |> atom_job_address_attrs()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    else
      %{}
    end
  end

  defp address_key_present?(map) do
    keys = [
      "address",
      "billing_address",
      "billing_address_different",
      "address_line1",
      "address_line2",
      "city",
      "state",
      "postal_code",
      "billing_address_line1",
      "billing_address_line2",
      "billing_city",
      "billing_state",
      "billing_postal_code"
    ]

    Enum.any?(keys, fn k ->
      Map.has_key?(map, k) or Map.has_key?(map, String.to_atom(k))
    end)
  end

  def same_address?(a, b) when is_map(a) and is_map(b) do
    normalize_compare_map(a) == normalize_compare_map(b)
  end

  defp normalize_compare_map(map) do
    map
    |> stringify_keys()
    |> Map.take(["address_line1", "address_line2", "city", "state", "postal_code"])
    |> Map.new(fn {k, v} -> {k, (v || "") |> to_string() |> String.trim() |> String.downcase()} end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp blank_to_nil(v) do
    case v |> to_string() |> String.trim() do
      "" -> nil
      s -> s
    end
  end

  defp truthy?(v) when v in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_), do: false
end
