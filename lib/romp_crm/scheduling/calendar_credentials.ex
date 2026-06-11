defmodule RompCrm.Scheduling.CalendarCredentials do
  @moduledoc """
  Per-user external calendar connections. Secret material is encrypted at rest
  via `RompCrm.Scheduling.CredentialCrypto`; nothing here ever logs or returns
  plaintext beyond `decrypt_credentials/1`.
  """

  import Ecto.Query

  alias RompCrm.Repo
  alias RompCrm.Scheduling.{CalendarCredential, CredentialCrypto}

  @doc "Creates or replaces the credential for `user_id` + `source` (\"google\" | \"apple\")."
  def connect(user_id, source, %{} = credentials) when is_integer(user_id) do
    attrs = %{
      user_id: user_id,
      source: source,
      encrypted_credentials: CredentialCrypto.encrypt(credentials),
      status: "connected",
      last_sync_error: nil
    }

    case Repo.get_by(CalendarCredential, user_id: user_id, source: source) do
      nil -> %CalendarCredential{} |> CalendarCredential.changeset(attrs) |> Repo.insert()
      existing -> existing |> CalendarCredential.changeset(attrs) |> Repo.update()
    end
  end

  def get(user_id, source) when is_integer(user_id) do
    Repo.get_by(CalendarCredential, user_id: user_id, source: source)
  end

  def list_for_user(user_id) when is_integer(user_id) do
    Repo.all(from c in CalendarCredential, where: c.user_id == ^user_id, order_by: c.source)
  end

  def disconnect(user_id, source) when is_integer(user_id) do
    case get(user_id, source) do
      nil -> :ok
      cred -> Repo.delete(cred) && :ok
    end
  end

  def decrypt_credentials(%CalendarCredential{encrypted_credentials: blob}) do
    CredentialCrypto.decrypt(blob)
  end

  @doc "Replaces stored secret material (e.g. after a token refresh)."
  def update_credentials(%CalendarCredential{} = cred, %{} = credentials) do
    cred
    |> CalendarCredential.changeset(%{encrypted_credentials: CredentialCrypto.encrypt(credentials)})
    |> Repo.update()
  end

  def mark_error(%CalendarCredential{} = cred, message) do
    cred
    |> CalendarCredential.changeset(%{
      status: "error",
      last_sync_error: message |> to_string() |> String.slice(0, 500)
    })
    |> Repo.update()
  end

  def mark_synced(%CalendarCredential{} = cred) do
    cred
    |> CalendarCredential.changeset(%{
      status: "connected",
      last_sync_error: nil,
      last_synced_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end
end
