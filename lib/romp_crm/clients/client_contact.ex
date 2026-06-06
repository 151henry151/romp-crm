defmodule RompCrm.Clients.ClientContact do
  @moduledoc """
  Shared client/contact field names mirrored on **`clients`** and copied onto **`jobs`**
  when linked or displayed.
  """

  @contact_fields [
    :client_name,
    :phone,
    :client_email,
    :address,
    :address_line1,
    :address_line2,
    :city,
    :state,
    :postal_code,
    :billing_address_different,
    :billing_address_line1,
    :billing_address_line2,
    :billing_city,
    :billing_state,
    :billing_postal_code,
    :notes
  ]

  @identity_fields [
    :client_name,
    :address,
    :address_line1,
    :phone,
    :client_email,
    :notes
  ]

  def contact_fields, do: @contact_fields
  def identity_fields, do: @identity_fields

  def from_map(%{} = source) do
    Enum.reduce(@contact_fields, %{}, fn field, acc ->
      val = Map.get(source, field) || Map.get(source, Atom.to_string(field))
      Map.put(acc, field, val)
    end)
  end

  def from_struct(%_{} = struct) do
    Map.take(Map.from_struct(struct), @contact_fields)
  end

  def to_job_attrs(%{} = contact) do
    contact
    |> Map.take(@contact_fields)
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Map.new()
  end

  def has_identity?(source) do
    Enum.any?(@identity_fields, fn field ->
      val = Map.get(source, field) || Map.get(source, to_string(field))

      case val do
        v when is_binary(v) -> String.trim(v) != ""
        _ -> false
      end
    end)
  end

  def normalize_name(name) do
    name |> to_string() |> String.trim() |> String.downcase()
  end

  def normalize_phone_key(phone) do
    case RompCrm.ContactInfo.normalize_phone(phone) do
      {:ok, nil} -> ""
      {:ok, e164} -> e164
      {:error, _} -> phone |> to_string() |> String.trim() |> String.downcase()
    end
  end

  def normalize_address_key(%{} = source) do
    parts = [
      Map.get(source, :address_line1) || Map.get(source, "address_line1"),
      Map.get(source, :city) || Map.get(source, "city"),
      Map.get(source, :state) || Map.get(source, "state"),
      Map.get(source, :postal_code) || Map.get(source, "postal_code"),
      Map.get(source, :address) || Map.get(source, "address")
    ]

    parts
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("|")
  end

  @doc """
  Whether two contact maps refer to the same client for backfill / dedupe.

  - All of name, phone, address keys match (blank equals blank), or
  - Names match and at least one side has **both** phone and address blank.
  """
  def same_client?(a, b) when is_map(a) and is_map(b) do
    name_a = normalize_name(Map.get(a, :client_name) || Map.get(a, "client_name") || "")
    name_b = normalize_name(Map.get(b, :client_name) || Map.get(b, "client_name") || "")

    if name_a == "" or name_a != name_b do
      false
    else
      phone_a = normalize_phone_key(Map.get(a, :phone) || Map.get(a, "phone") || "")
      phone_b = normalize_phone_key(Map.get(b, :phone) || Map.get(b, "phone") || "")
      addr_a = normalize_address_key(a)
      addr_b = normalize_address_key(b)

      (phone_a == phone_b and addr_a == addr_b) or sparse_name_only?(a) or sparse_name_only?(b)
    end
  end

  defp sparse_name_only?(source) do
    phone =
      (Map.get(source, :phone) || Map.get(source, "phone") || "")
      |> to_string()
      |> String.trim()

    addr = normalize_address_key(source)
    phone == "" and addr == ""
  end
end
