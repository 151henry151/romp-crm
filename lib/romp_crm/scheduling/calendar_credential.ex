defmodule RompCrm.Scheduling.CalendarCredential do
  @moduledoc """
  Per-user external calendar connection (`google` or `apple`), read-only.
  Secret material lives in `encrypted_credentials` (AES-256-GCM, see
  `RompCrm.Scheduling.CredentialCrypto`); plaintext is never persisted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(google apple)
  @statuses ~w(connected error disconnected)

  schema "calendar_credentials" do
    belongs_to :user, RompCrm.Accounts.User

    field :source, :string
    field :encrypted_credentials, :binary, redact: true
    field :status, :string, default: "connected"
    field :last_sync_error, :string
    field :last_synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def sources, do: @sources

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:user_id, :source, :encrypted_credentials, :status, :last_sync_error, :last_synced_at])
    |> validate_required([:user_id, :source, :encrypted_credentials, :status])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :source])
  end
end
