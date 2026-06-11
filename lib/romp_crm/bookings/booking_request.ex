defmodule RompCrm.Bookings.BookingRequest do
  @moduledoc """
  Soft availability: the client's raw availability text plus any windows the agent
  could parse from it, awaiting technician confirmation into a `Booking`.

  `parsed_windows_json` holds a JSON list of `%{"start" => iso8601, "end" => iso8601}` UTC windows.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending confirmed converted cancelled)

  schema "booking_requests" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :technician_user, RompCrm.Accounts.User
    belongs_to :booking_link, RompCrm.Bookings.BookingLink
    belongs_to :client, RompCrm.Clients.Client

    field :availability_text, :string, default: ""
    field :parsed_windows_json, :string
    field :job_type_label, :string, default: ""
    field :duration_min_minutes, :integer
    field :duration_max_minutes, :integer
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :business_id,
      :technician_user_id,
      :booking_link_id,
      :client_id,
      :availability_text,
      :parsed_windows_json,
      :job_type_label,
      :duration_min_minutes,
      :duration_max_minutes,
      :status
    ])
    |> validate_required([:business_id, :technician_user_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:availability_text, max: 4000)
    |> validate_length(:job_type_label, max: 200)
  end

  @doc "Decodes `parsed_windows_json` into `[%{start: DateTime, end: DateTime}]`; bad data yields `[]`."
  def parsed_windows(%__MODULE__{parsed_windows_json: nil}), do: []

  def parsed_windows(%__MODULE__{parsed_windows_json: json}) when is_binary(json) do
    with {:ok, list} when is_list(list) <- Jason.decode(json) do
      Enum.flat_map(list, fn
        %{"start" => s, "end" => e} ->
          with {:ok, start_dt, _} <- DateTime.from_iso8601(to_string(s)),
               {:ok, end_dt, _} <- DateTime.from_iso8601(to_string(e)) do
            [%{start: start_dt, end: end_dt}]
          else
            _ -> []
          end

        _ ->
          []
      end)
    else
      _ -> []
    end
  end
end
