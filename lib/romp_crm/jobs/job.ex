defmodule RompCrm.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @priorities [:normal, :high]
  @statuses [:lead, :pending, :in_progress, :done]

  def priorities, do: @priorities
  def statuses, do: @statuses

  schema "jobs" do
    belongs_to :business, RompCrm.Businesses.Business

    field :client_name, :string
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
    field :phone, :string
    field :client_email, :string
    field :work_description, :string
    field :priority, Ecto.Enum, values: @priorities, default: :normal
    field :status, Ecto.Enum, values: @statuses, default: :lead
    field :referred_by, :string
    field :notes, :string
    field :next_action, :string
    field :scheduled_on, :date
    field :scheduled_time, :time

    has_many :work_items, RompCrm.Jobs.JobWorkItem, on_replace: :delete
    has_many :materials, RompCrm.Jobs.JobMaterial
    has_many :photos, RompCrm.Jobs.JobPhoto

    timestamps(type: :utc_datetime)
  end

  alias RompCrm.Addresses

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

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :business_id,
      :client_name,
      :phone,
      :client_email,
      :work_description,
      :priority,
      :status,
      :referred_by,
      :notes,
      :next_action,
      :scheduled_on,
      :scheduled_time
    ] ++ @address_fields)
    |> normalize_billing_address_different()
    |> maybe_clear_billing_fields()
    |> put_legacy_address()
    |> cast_assoc(:work_items,
      with: &RompCrm.Jobs.JobWorkItem.changeset/2,
      sort_param: :work_items_sort,
      drop_param: :work_items_drop
    )
    |> validate_required([:business_id, :client_name, :priority, :status])
    |> RompCrm.ContactInfo.validate_job_changeset()
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
