defmodule RompCrm.Scheduling.CredentialCryptoTest do
  use ExUnit.Case, async: true

  alias RompCrm.Scheduling.CredentialCrypto

  @payload %{"access_token" => "ya29.secret", "refresh_token" => "1//refresh", "expires_at" => 1_900_000_000}

  test "encrypt/decrypt round-trips a credential map" do
    blob = CredentialCrypto.encrypt(@payload)
    assert is_binary(blob)
    assert {:ok, @payload} == CredentialCrypto.decrypt(blob)
  end

  test "ciphertext differs across calls (random IV)" do
    assert CredentialCrypto.encrypt(@payload) != CredentialCrypto.encrypt(@payload)
  end

  test "tampered ciphertext fails closed" do
    blob = CredentialCrypto.encrypt(@payload)
    <<head::binary-size(byte_size(blob) - 1), last>> = blob
    tampered = head <> <<Bitwise.bxor(last, 1)>>

    assert :error == CredentialCrypto.decrypt(tampered)
  end

  test "garbage input fails closed" do
    assert :error == CredentialCrypto.decrypt("not a blob")
    assert :error == CredentialCrypto.decrypt(<<>>)
  end
end
