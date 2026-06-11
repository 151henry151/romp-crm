defmodule RompCrm.SchedulingTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Scheduling
  alias RompCrm.Scheduling.CalendarCredentials

  defmodule FakeBusySource do
    @behaviour RompCrm.Scheduling.CalendarSource

    @impl true
    def fetch_busy_blocks(_cred, _range, _tz) do
      {:ok, [%{start: ~U[2026-06-15 14:00:00Z], end: ~U[2026-06-15 15:00:00Z]}]}
    end
  end

  defmodule FailingSource do
    @behaviour RompCrm.Scheduling.CalendarSource

    @impl true
    def fetch_busy_blocks(_cred, _range, _tz), do: {:error, :boom}
  end

  setup do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business}
  end

  describe "combined_busy_blocks/4" do
    test "returns internal blocks when no external calendars connected", %{
      user: user,
      business: business
    } do
      assert {:ok, blocks} =
               Scheduling.combined_busy_blocks(
                 business.id,
                 user.id,
                 {~D[2026-06-15], ~D[2026-06-16]},
                 "America/New_York"
               )

      assert blocks == []
    end

    test "merges external busy blocks from connected sources", %{user: user, business: business} do
      {:ok, _} = CalendarCredentials.connect(user.id, "google", %{"access_token" => "t"})

      prev = Application.get_env(:romp_crm, :calendar_source_overrides)
      Application.put_env(:romp_crm, :calendar_source_overrides, %{"google" => FakeBusySource})
      on_exit(fn -> Application.put_env(:romp_crm, :calendar_source_overrides, prev) end)

      assert {:ok, blocks} =
               Scheduling.combined_busy_blocks(
                 business.id,
                 user.id,
                 {~D[2026-06-15], ~D[2026-06-16]},
                 "America/New_York"
               )

      assert blocks == [%{start: ~U[2026-06-15 14:00:00Z], end: ~U[2026-06-15 15:00:00Z]}]
    end

    test "a failing external source degrades gracefully to internal blocks", %{
      user: user,
      business: business
    } do
      {:ok, _} = CalendarCredentials.connect(user.id, "apple", %{"apple_id" => "x"})

      prev = Application.get_env(:romp_crm, :calendar_source_overrides)
      Application.put_env(:romp_crm, :calendar_source_overrides, %{"apple" => FailingSource})
      on_exit(fn -> Application.put_env(:romp_crm, :calendar_source_overrides, prev) end)

      assert {:ok, []} =
               Scheduling.combined_busy_blocks(
                 business.id,
                 user.id,
                 {~D[2026-06-15], ~D[2026-06-16]},
                 "America/New_York"
               )
    end

    test "skips disconnected credentials", %{user: user, business: business} do
      {:ok, _} = CalendarCredentials.connect(user.id, "google", %{"access_token" => "t"})
      :ok = CalendarCredentials.disconnect(user.id, "google")

      prev = Application.get_env(:romp_crm, :calendar_source_overrides)
      Application.put_env(:romp_crm, :calendar_source_overrides, %{"google" => FailingSource})
      on_exit(fn -> Application.put_env(:romp_crm, :calendar_source_overrides, prev) end)

      assert {:ok, []} =
               Scheduling.combined_busy_blocks(
                 business.id,
                 user.id,
                 {~D[2026-06-15], ~D[2026-06-16]},
                 "America/New_York"
               )
    end
  end
end
