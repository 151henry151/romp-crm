defmodule RompCrm.Scheduling.CalendarCredentialsTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Scheduling.CalendarCredentials

  setup do
    %{user: user_fixture()}
  end

  test "connect/3 stores encrypted credentials retrievable via decrypt", %{user: user} do
    creds = %{"access_token" => "tok", "refresh_token" => "ref", "expires_at" => 1_900_000_000}

    assert {:ok, cred} = CalendarCredentials.connect(user.id, "google", creds)
    assert cred.status == "connected"
    refute cred.encrypted_credentials =~ "tok"

    assert {:ok, ^creds} = CalendarCredentials.decrypt_credentials(cred)
  end

  test "connect/3 upserts per user+source", %{user: user} do
    {:ok, _} = CalendarCredentials.connect(user.id, "google", %{"access_token" => "a"})
    {:ok, cred} = CalendarCredentials.connect(user.id, "google", %{"access_token" => "b"})

    assert [only] = CalendarCredentials.list_for_user(user.id)
    assert only.id == cred.id
    assert {:ok, %{"access_token" => "b"}} = CalendarCredentials.decrypt_credentials(only)
  end

  test "disconnect/2 removes the credential", %{user: user} do
    {:ok, _} = CalendarCredentials.connect(user.id, "apple", %{"apple_id" => "x@icloud.com"})
    assert :ok = CalendarCredentials.disconnect(user.id, "apple")
    assert CalendarCredentials.get(user.id, "apple") == nil
    assert :ok = CalendarCredentials.disconnect(user.id, "apple")
  end

  test "mark_error/2 and mark_synced/1 update status fields", %{user: user} do
    {:ok, cred} = CalendarCredentials.connect(user.id, "google", %{"access_token" => "a"})

    {:ok, errored} = CalendarCredentials.mark_error(cred, "401 unauthorized")
    assert errored.status == "error"
    assert errored.last_sync_error == "401 unauthorized"

    {:ok, synced} = CalendarCredentials.mark_synced(errored)
    assert synced.status == "connected"
    assert synced.last_sync_error == nil
    assert %DateTime{} = synced.last_synced_at
  end

  test "update_credentials/2 re-encrypts new material", %{user: user} do
    {:ok, cred} = CalendarCredentials.connect(user.id, "google", %{"access_token" => "old"})
    {:ok, updated} = CalendarCredentials.update_credentials(cred, %{"access_token" => "new"})

    assert {:ok, %{"access_token" => "new"}} = CalendarCredentials.decrypt_credentials(updated)
  end
end
