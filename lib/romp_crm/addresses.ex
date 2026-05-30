defmodule RompCrm.Addresses do
  @moduledoc """
  Structured service and billing address helpers for jobs.
  """

  @service_fields ~w(address_line1 address_line2 city state postal_code)a
  @billing_fields ~w(billing_address_line1 billing_address_line2 billing_city billing_state billing_postal_code)a
  @us_state_abbreviations ~w(
    AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC
  )

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
      parse_us_address(trimmed)
    end
  end

  def from_legacy_string(_), do: %{}

  @doc """
  When an AI/SMS patch touches address fields, merge with the job's existing address,
  parse legacy strings, normalize casing, and geocode when possible to fill ZIP and
  structured fields.
  """
  def enrich_ai_address_update(%_{} = job, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    if address_key_present?(attrs) do
      attrs
      |> merge_ai_address_attrs()
      |> enrich_service_address_from_job(job)
      |> enrich_billing_address_from_job(job)
    else
      attrs
    end
  end

  def enrich_ai_address_update(_job, attrs), do: attrs

  @doc """
  Parse a US-style free-text address into structured service fields.
  Handles comma-separated forms like `"South St, Middlebury VT"`.
  """
  def parse_us_address(address) when is_binary(address) do
    trimmed = String.trim(address)

    cond do
      trimmed == "" ->
        %{}

      String.contains?(trimmed, ",") ->
        parse_comma_address(trimmed)

      true ->
        case parse_trailing_city_state(trimmed) do
          {street, city, state, zip} when is_binary(street) ->
            service_parts_map(street, nil, city, state, zip)

          :no_match ->
            service_parts_map(trimmed, nil, nil, nil, nil)
        end
    end
    |> normalize_service_parts()
  end

  def parse_us_address(_), do: %{}

  defp enrich_service_address_from_job(attrs, job) do
    incoming = extract_service_parts(attrs)
    existing = existing_service_parts(job)
    merged = merge_service_parts(existing, incoming)

    merged
    |> geocode_enrich_service_parts()
    |> apply_service_parts_to_attrs(attrs)
  end

  defp enrich_billing_address_from_job(attrs, job) do
    if billing_key_present?(attrs) do
      incoming = extract_billing_parts(attrs)
      existing = existing_billing_parts(job)
      merged = merge_billing_parts(existing, incoming)

      merged
      |> geocode_enrich_billing_parts()
      |> apply_billing_parts_to_attrs(attrs)
    else
      attrs
    end
  end

  defp existing_service_parts(job) do
    base =
      service_parts_map(
        job.address_line1,
        job.address_line2,
        job.city,
        job.state,
        job.postal_code
      )

    legacy_sources =
      [job.address, job.address_line1]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Enum.reduce(legacy_sources, base, fn legacy, acc ->
      merge_service_parts(acc, parse_us_address(legacy))
    end)
  end

  defp existing_billing_parts(job) do
    if job.billing_address_different do
      base =
        billing_parts_map(
          job.billing_address_line1,
          job.billing_address_line2,
          job.billing_city,
          job.billing_state,
          job.billing_postal_code
        )

      case blank_to_nil(job.billing_address_line1) do
        nil ->
          base

        line1 ->
          merge_billing_parts(base, billing_from_service(parse_us_address(line1)))
      end
    else
      billing_parts_map(nil, nil, nil, nil, nil)
    end
  end

  defp extract_service_parts(attrs) do
    attrs
    |> Map.take(Enum.map(@service_fields, &to_string/1))
    |> Enum.map(fn {k, v} -> {k, blank_to_nil(v)} end)
    |> Map.new()
    |> normalize_service_parts()
  end

  defp extract_billing_parts(attrs) do
    attrs
    |> Map.take(Enum.map(@billing_fields, &to_string/1))
    |> Enum.map(fn {k, v} -> {k, blank_to_nil(v)} end)
    |> Map.new()
    |> normalize_billing_parts()
  end

  defp merge_service_parts(existing, incoming) do
    merge_parts(existing, incoming, @service_fields)
  end

  defp merge_billing_parts(existing, incoming) do
    merge_parts(existing, incoming, @billing_fields)
  end

  defp merge_parts(existing, incoming, fields) do
    Enum.reduce(fields, existing, fn field, acc ->
      key = to_string(field)
      incoming_val = blank_to_nil(Map.get(incoming, key))
      existing_val = blank_to_nil(Map.get(acc, key))

      if incoming_val do
        Map.put(acc, key, incoming_val)
      else
        if existing_val, do: acc, else: Map.put(acc, key, nil)
      end
    end)
  end

  defp geocode_enrich_service_parts(parts) do
    case format_parts(parts) do
      "" ->
        parts

      _ ->
        case RompCrm.GoogleMaps.geocode_service(parts) do
          {:ok, geo} -> merge_geocode_service_parts(parts, geo)
          _ -> parts
        end
    end
  end

  defp geocode_enrich_billing_parts(parts) do
    service_parts =
      parts
      |> Map.new(fn {k, v} -> {String.replace_prefix(k, "billing_", ""), v} end)

    case format_parts(service_parts) do
      "" ->
        parts

      _ ->
        case RompCrm.GoogleMaps.geocode_service(service_parts) do
          {:ok, geo} ->
            billing_geo = Map.new(geo, fn {k, v} -> {"billing_" <> k, v} end)
            merge_geocode_billing_parts(parts, billing_geo)

          _ ->
            parts
        end
    end
  end

  defp merge_geocode_service_parts(local, geo) do
    geo =
      geo
      |> Map.drop(["formatted"])
      |> Map.new(fn {k, v} -> {k, blank_to_nil(v)} end)

    Enum.reduce(geo, local, fn {k, v}, acc ->
      if v, do: Map.put(acc, k, v), else: acc
    end)
    |> normalize_service_parts()
  end

  defp merge_geocode_billing_parts(local, geo) do
    geo =
      geo
      |> Map.drop(["billing_formatted"])
      |> Map.new(fn {k, v} -> {k, blank_to_nil(v)} end)

    Enum.reduce(geo, local, fn {k, v}, acc ->
      if v, do: Map.put(acc, k, v), else: acc
    end)
    |> normalize_billing_parts()
  end

  defp apply_service_parts_to_attrs(parts, attrs) do
    attrs
    |> Map.merge(parts)
    |> Map.put("address", format_parts(parts))
  end

  defp apply_billing_parts_to_attrs(parts, attrs) do
    Map.merge(attrs, parts)
  end

  defp parse_comma_address(trimmed) do
    segments =
      trimmed
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case segments do
      [line1] ->
        service_parts_map(line1, nil, nil, nil, nil)

      [line1, tail] ->
        {city, state, zip} = parse_city_state_zip_segment(tail)
        service_parts_map(line1, nil, city, state, zip)

      [line1, city | rest] ->
        tail = Enum.join(rest, ", ")
        {_, state, zip} = parse_city_state_zip_segment(tail)
        service_parts_map(line1, nil, city, state, zip)
    end
  end

  defp parse_trailing_city_state(text) do
    case Regex.run(~r/^(?<street>.+?)\s+(?<city>[A-Za-z .'-]+)\s+(?<state>[A-Za-z]{2})(?:\s+(?<zip>\d{5}(?:-\d{4})?))?\z/i, text) do
      [_, street, city, state | rest] ->
        state = normalize_state(state)

        if valid_state_abbrev?(state) do
          zip = rest |> List.first() |> blank_to_nil()
          {String.trim(street), String.trim(city), state, zip}
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  defp parse_city_state_zip_segment(segment) do
    cond do
      match = Regex.run(~r/^(?<city>.+?)\s+(?<state>[A-Za-z]{2})(?:\s+(?<zip>\d{5}(?:-\d{4})?))?\z/i, segment) ->
        [_, city, state | rest] = match
        state = normalize_state(state)

        if valid_state_abbrev?(state) do
          zip = rest |> List.first() |> blank_to_nil()
          {String.trim(city), state, zip}
        else
          {segment, nil, nil}
        end

      match = Regex.run(~r/^(?<state>[A-Za-z]{2})(?:\s+(?<zip>\d{5}(?:-\d{4})?))?\z/i, segment) ->
        [_, state | rest] = match
        state = normalize_state(state)

        if valid_state_abbrev?(state) do
          zip = rest |> List.first() |> blank_to_nil()
          {nil, state, zip}
        else
          {segment, nil, nil}
        end

      true ->
        {segment, nil, nil}
    end
  end

  defp valid_state_abbrev?(state) when is_binary(state), do: state in @us_state_abbreviations
  defp valid_state_abbrev?(_), do: false

  defp service_parts_map(line1, line2, city, state, postal) do
    %{
      "address_line1" => blank_to_nil(line1),
      "address_line2" => blank_to_nil(line2),
      "city" => blank_to_nil(city),
      "state" => normalize_state(state),
      "postal_code" => blank_to_nil(postal)
    }
  end

  defp billing_parts_map(line1, line2, city, state, postal) do
    %{
      "billing_address_line1" => blank_to_nil(line1),
      "billing_address_line2" => blank_to_nil(line2),
      "billing_city" => blank_to_nil(city),
      "billing_state" => normalize_state(state),
      "billing_postal_code" => blank_to_nil(postal)
    }
  end

  defp billing_from_service(%{} = parts) do
    %{
      "billing_address_line1" => parts["address_line1"],
      "billing_address_line2" => parts["address_line2"],
      "billing_city" => parts["city"],
      "billing_state" => parts["state"],
      "billing_postal_code" => parts["postal_code"]
    }
  end

  defp normalize_service_parts(%{} = parts) do
    parts
    |> Map.update("address_line1", nil, &normalize_street_line/1)
    |> Map.update("address_line2", nil, &normalize_street_line/1)
    |> Map.update("city", nil, &normalize_city/1)
    |> Map.update("state", nil, &normalize_state/1)
    |> Map.update("postal_code", nil, &normalize_postal/1)
  end

  defp normalize_billing_parts(%{} = parts) do
    parts
    |> Map.update("billing_address_line1", nil, &normalize_street_line/1)
    |> Map.update("billing_address_line2", nil, &normalize_street_line/1)
    |> Map.update("billing_city", nil, &normalize_city/1)
    |> Map.update("billing_state", nil, &normalize_state/1)
    |> Map.update("billing_postal_code", nil, &normalize_postal/1)
  end

  defp normalize_street_line(nil), do: nil

  defp normalize_street_line(line) when is_binary(line) do
    line
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&normalize_street_token/1)
    |> Enum.join(" ")
  end

  defp normalize_street_token(token) do
    cond do
      String.match?(token, ~r/^\d+[A-Za-z]?$/) ->
        token |> String.upcase()

      String.match?(token, ~r/^[NSEW]\.?$/i) ->
        token |> String.replace(".", "") |> String.upcase()

      String.upcase(token) in ~w(PO RR HC FM APT STE) ->
        String.upcase(token)

      true ->
        String.capitalize(String.downcase(token))
    end
  end

  defp normalize_city(nil), do: nil

  defp normalize_city(city) when is_binary(city) do
    city
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn word -> word |> String.downcase() |> String.capitalize() end)
    |> Enum.join(" ")
  end

  defp normalize_state(nil), do: nil

  defp normalize_state(state) when is_binary(state) do
    state |> String.trim() |> String.upcase()
  end

  defp normalize_state(_), do: nil

  defp normalize_postal(nil), do: nil

  defp normalize_postal(postal) when is_binary(postal) do
    case Regex.run(~r/^(\d{5})/, String.trim(postal)) do
      [_, zip] -> zip
      _ -> postal
    end
  end

  defp billing_key_present?(map) do
    keys = [
      "billing_address",
      "billing_address_different",
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
