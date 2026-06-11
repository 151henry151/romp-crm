defmodule RompCrm.Bookings.Escalation do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending_contractor pending_memory_confirm contractor_handling resolved)

  schema "booking_escalations" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :technician_user, RompCrm.Accounts.User
    belongs_to :booking_link, RompCrm.Bookings.BookingLink
    belongs_to :client, RompCrm.Clients.Client

    field :client_phone_normalized, :string
    field :client_name, :string, default: ""
    field :question_text, :string
    field :status, :string, default: "pending_contractor"
    field :contractor_answer, :string
    field :memory_candidate, :string
    field :memory_saved, :boolean, default: false
    field :client_relayed_at, :utc_datetime
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(escalation, attrs) do
    escalation
    |> cast(attrs, [
      :business_id,
      :technician_user_id,
      :booking_link_id,
      :client_id,
      :client_phone_normalized,
      :client_name,
      :question_text,
      :status,
      :contractor_answer,
      :memory_candidate,
      :memory_saved,
      :client_relayed_at,
      :resolved_at
    ])
    |> validate_required([
      :business_id,
      :technician_user_id,
      :client_phone_normalized,
      :question_text,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:client_name, max: 200)
  end
end
