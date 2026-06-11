defmodule RompCrm.Scheduling.GoogleCalendarSourceTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Scheduling.CalendarCredentials
  alias RompCrm.Scheduling.GoogleCalendarSource

  @range {~D[2026-06-15], ~D[2026-06-16]}
  @tz "America/New_York"

  setup do
    Req.Test.stub(GoogleCalendarSource, fn conn ->
      Req.Test.json(conn, %{})
    end)

    prev = Application.get_env(:romp_crm, :calendar_http_options)
    Application.put_env(:romp_crm, :calendar_http_options, plug: {Req.Test, GoogleCalendarSource})

    prev_oauth = Application.get_env(:romp_crm, :google_calendar_oauth)

    Application.put_env(:romp_crm, :google_calendar_oauth,
      client_id: "test-client",
      client_secret: "test-secret"
    )

    on_exit(fn ->
      Application.put_env(:romp_crm, :calendar_http_options, prev)
      Application.put_env(:romp_crm, :google_calendar_oauth, prev_oauth)
    end)

    %{user: user_fixture()}
  end

  defp fresh_creds do
    %{
      "access_token" => "fresh-token",
      "refresh_token" => "refresh-1",
      "expires_at" => System.os_time(:second) + 3600
    }
  end

  test "fetches and parses freebusy blocks", %{user: user} do
    {:ok, cred} = CalendarCredentials.connect(user.id, "google", fresh_creds())

    Req.Test.stub(GoogleCalendarSource, fn conn ->
      assert conn.method == "POST"

      Req.Test.json(conn, %{
        "calendars" => %{
          "primary" => %{
            "busy" => [
              %{"start" => "2026-06-15T14:00:00Z", "end" => "2026-06-15T16:00:00Z"},
              %{"start" => "2026-06-16T13:00:00Z", "end" => "2026-06-16T13:30:00Z"}
            ]
          }
        }
      })
    end)

    assert {:ok, blocks} = GoogleCalendarSource.fetch_busy_blocks(cred, @range, @tz)

    assert blocks == [
             %{start: ~U[2026-06-15 14:00:00Z], end: ~U[2026-06-15 16:00:00Z]},
             %{start: ~U[2026-06-16 13:00:00Z], end: ~U[2026-06-16 13:30:00Z]}
           ]

    assert Repo.reload!(cred).status == "connected"
  end

  test "refreshes an expired token before fetching and persists it", %{user: user} do
    {:ok, cred} =
      CalendarCredentials.connect(user.id, "google", %{
        "access_token" => "stale-token",
        "refresh_token" => "refresh-1",
        "expires_at" => System.os_time(:second) - 10
      })

    Req.Test.stub(GoogleCalendarSource, fn conn ->
      if String.contains?(conn.request_path, "token") do
        Req.Test.json(conn, %{"access_token" => "minted-token", "expires_in" => 3599})
      else
        assert ["Bearer minted-token"] = Plug.Conn.get_req_header(conn, "authorization")
        Req.Test.json(conn, %{"calendars" => %{"primary" => %{"busy" => []}}})
      end
    end)

    assert {:ok, []} = GoogleCalendarSource.fetch_busy_blocks(cred, @range, @tz)

    {:ok, stored} = CalendarCredentials.decrypt_credentials(Repo.reload!(cred))
    assert stored["access_token"] == "minted-token"
    assert stored["refresh_token"] == "refresh-1"
  end

  test "API error marks the credential errored", %{user: user} do
    {:ok, cred} = CalendarCredentials.connect(user.id, "google", fresh_creds())

    Req.Test.stub(GoogleCalendarSource, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
    end)

    assert {:error, _} = GoogleCalendarSource.fetch_busy_blocks(cred, @range, @tz)

    reloaded = Repo.reload!(cred)
    assert reloaded.status == "error"
    assert reloaded.last_sync_error =~ "401"
  end
end
