defmodule RompCrm.Scheduling.CredentialCrypto do
  @moduledoc """
  AES-256-GCM encryption for calendar credentials at rest.

  Blob layout: `"v1" <> iv (12 bytes) <> tag (16 bytes) <> ciphertext`.
  The key derives from `:calendar_credentials_key` app config when set,
  otherwise from the endpoint `secret_key_base`, via HKDF-like hashing.
  """

  @aad "romp_crm calendar credential"

  @doc "Encrypts a JSON-serializable map; returns an opaque binary blob."
  def encrypt(%{} = credentials) do
    plaintext = Jason.encode!(credentials)
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plaintext, @aad, true)

    "v1" <> iv <> tag <> ciphertext
  end

  @doc "Decrypts a blob produced by `encrypt/1`; returns `{:ok, map}` or `:error`."
  def decrypt("v1" <> <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) ->
        case Jason.decode(plaintext) do
          {:ok, %{} = map} -> {:ok, map}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def decrypt(_), do: :error

  defp key do
    secret =
      Application.get_env(:romp_crm, :calendar_credentials_key) ||
        Application.fetch_env!(:romp_crm, RompCrmWeb.Endpoint)[:secret_key_base]

    :crypto.hash(:sha256, "calendar_credentials:" <> to_string(secret))
  end
end
