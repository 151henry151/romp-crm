defmodule RompCrm.Clients.Client do
  use Ecto.Schema
  import Ecto.Changeset

  alias RompCrm.Addresses
  alias RompCrm.Clients.ClientContact

  schema "clients" do
    belongs_to :business, RompCrm.Businesses.Business

    field :client_name, :string
    field :phone, :string
    field :client_email, :string
    field :address, :string
    field :address_line1, :string
    field :address_line2, :string
    field :city, :string
    field :state, :string
    field :postal_code, :string
    field :billing_address_different, :boolean, default: false
    field :billing_address_line1, :string
    field :billing_address_line2, :string
    field :billing_city, :string
    field :billing_state, :string
    field :billing_postal_code, :string
    field :notes, :string

    has_many :jobs, RompCrm.Jobs.Job

    timestamps(type: :utc_datetime)
  end

  @address_fields [
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
    :billing_postal_code
  ]

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:business_id, :client_name, :phone, :client_email, :notes] ++ @address_fields)
    |> normalize_billing_address_different()
    |> maybe_clear_billing_fields()
    |> put_legacy_address()
    |> normalize_blank_client_name()
    |> validate_required([:business_id])
    |> validate_client_has_identity()
    |> RompCrm.ContactInfo.validate_client_changeset()
  end

  defp normalize_blank_client_name(changeset) do
    case get_change(changeset, :client_name) || get_field(changeset, :client_name) do
      nil -> put_change(changeset, :client_name, "")
      name when is_binary(name) -> put_change(changeset, :client_name, String.trim(name))
      _ -> changeset
    end
  end

  defp validate_client_has_identity(changeset) do
    if client_has_identity?(changeset) do
      changeset
    else
      add_error(
        changeset,
        :client_name,
        "Enter a client name or at least one other detail (address, phone, email, notes)"
      )
    end
  end

  defp client_has_identity?(changeset) do
    Enum.any?(ClientContact.identity_fields(), fn field ->
      case get_change(changeset, field) || get_field(changeset, field) do
        val when is_binary(val) -> String.trim(val) != ""
        _ -> false
      end
    end)
  end

  defp normalize_billing_address_different(changeset) do
    case get_change(changeset, :billing_address_different) do
      values when is_list(values) ->
        truthy = Enum.any?(values, fn v -> v in [true, "true", "1", 1, "on"] end)
        put_change(changeset, :billing_address_different, truthy)

      v when v in [true, "true", "1", 1, "on"] ->
        put_change(changeset, :billing_address_different, true)

      v when v in [false, "false", "0", 0, nil, ""] ->
        put_change(changeset, :billing_address_different, false)

      _ ->
        changeset
    end
  end

  defp maybe_clear_billing_fields(changeset) do
    case get_change(changeset, :billing_address_different) do
      false ->
        changeset
        |> put_change(:billing_address_line1, nil)
        |> put_change(:billing_address_line2, nil)
        |> put_change(:billing_city, nil)
        |> put_change(:billing_state, nil)
        |> put_change(:billing_postal_code, nil)

      _ ->
        changeset
    end
  end

  defp put_legacy_address(changeset) do
    parts = %{
      "address_line1" => get_field(changeset, :address_line1),
      "address_line2" => get_field(changeset, :address_line2),
      "city" => get_field(changeset, :city),
      "state" => get_field(changeset, :state),
      "postal_code" => get_field(changeset, :postal_code)
    }

    formatted = Addresses.format_parts(parts)
    put_change(changeset, :address, if(formatted == "", do: nil, else: formatted))
  end
end
