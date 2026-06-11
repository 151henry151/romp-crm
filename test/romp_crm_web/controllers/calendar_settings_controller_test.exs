defmodule RompCrmWeb.CalendarSettingsControllerTest do
  use RompCrmWeb.ConnCase, async: false

  alias RompCrm.Repo
  alias RompCrm.Scheduling.CalendarCredentials
  alias RompCrm.Scheduling.Prefs

  setup :register_and_log_in_user

  describe "PUT /users/settings/scheduling" do
    test "saves scheduling preferences", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings/scheduling", %{
          "prefs" => %{
            "timezone" => "America/Chicago",
            "workday_start" => "07:30",
            "workday_end" => "16:00",
            "work_days" => ["1", "2", "3", "4", "5", "6"],
            "buffer_minutes" => "15"
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"

      prefs = Prefs.decode(Repo.reload!(user).scheduling_prefs_json)
      assert prefs.timezone == "America/Chicago"
      assert prefs.workday_start == ~T[07:30:00]
      assert prefs.workday_end == ~T[16:00:00]
      assert prefs.work_days == [1, 2, 3, 4, 5, 6]
      assert prefs.buffer_minutes == 15
    end

    test "invalid values fall back to defaults rather than erroring", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings/scheduling", %{
          "prefs" => %{"timezone" => "Not/AZone", "workday_start" => "huh"}
        })

      assert redirected_to(conn) == ~p"/users/settings"
      prefs = Prefs.decode(Repo.reload!(user).scheduling_prefs_json)
      assert prefs.timezone == "America/New_York"
    end
  end

  describe "POST /users/settings/calendars/apple" do
    test "connects with apple id and app-specific password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/settings/calendars/apple", %{
          "apple" => %{"apple_id" => "tech@icloud.com", "app_password" => "abcd-efgh-ijkl-mnop"}
        })

      assert redirected_to(conn) == ~p"/users/settings"

      cred = CalendarCredentials.get(user.id, "apple")
      assert cred.status == "connected"

      assert {:ok, %{"apple_id" => "tech@icloud.com", "app_password" => "abcd-efgh-ijkl-mnop"}} =
               CalendarCredentials.decrypt_credentials(cred)
    end

    test "rejects blank fields", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/settings/calendars/apple", %{
          "apple" => %{"apple_id" => "", "app_password" => ""}
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Apple ID"
      assert CalendarCredentials.get(user.id, "apple") == nil
    end
  end

  describe "POST /users/settings/calendars/:source/disconnect" do
    test "removes the credential", %{conn: conn, user: user} do
      {:ok, _} = CalendarCredentials.connect(user.id, "apple", %{"apple_id" => "x"})

      conn = post(conn, ~p"/users/settings/calendars/apple/disconnect")

      assert redirected_to(conn) == ~p"/users/settings"
      assert CalendarCredentials.get(user.id, "apple") == nil
    end
  end

  describe "GET /users/settings/calendars/google/connect" do
    test "redirects to Google consent when oauth is configured", %{conn: conn} do
      prev = Application.get_env(:romp_crm, :google_calendar_oauth)

      Application.put_env(:romp_crm, :google_calendar_oauth,
        client_id: "test-client",
        client_secret: "shh"
      )

      on_exit(fn -> Application.put_env(:romp_crm, :google_calendar_oauth, prev) end)

      conn = get(conn, ~p"/users/settings/calendars/google/connect")

      location = redirected_to(conn)
      assert location =~ "accounts.google.com/o/oauth2/v2/auth"
      assert location =~ "test-client"
      assert location =~ "calendar.freebusy"
      assert get_session(conn, :google_calendar_oauth_state)
    end

    test "flashes an error when oauth is not configured", %{conn: conn} do
      prev = Application.get_env(:romp_crm, :google_calendar_oauth)
      Application.put_env(:romp_crm, :google_calendar_oauth, [])
      on_exit(fn -> Application.put_env(:romp_crm, :google_calendar_oauth, prev) end)

      conn = get(conn, ~p"/users/settings/calendars/google/connect")
      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not configured"
    end
  end

  describe "GET /users/settings/calendars/google/callback" do
    setup %{conn: conn} do
      prev_oauth = Application.get_env(:romp_crm, :google_calendar_oauth)
      prev_http = Application.get_env(:romp_crm, :calendar_http_options)

      Application.put_env(:romp_crm, :google_calendar_oauth,
        client_id: "test-client",
        client_secret: "shh"
      )

      Application.put_env(:romp_crm, :calendar_http_options,
        plug: {Req.Test, RompCrmWeb.CalendarSettingsController}
      )

      on_exit(fn ->
        Application.put_env(:romp_crm, :google_calendar_oauth, prev_oauth)
        Application.put_env(:romp_crm, :calendar_http_options, prev_http)
      end)

      conn = init_test_session(conn, %{google_calendar_oauth_state: "expected-state"})
      %{conn: conn}
    end

    test "exchanges the code and stores tokens", %{conn: conn, user: user} do
      Req.Test.stub(RompCrmWeb.CalendarSettingsController, fn conn ->
        Req.Test.json(conn, %{
          "access_token" => "at-123",
          "refresh_token" => "rt-456",
          "expires_in" => 3599
        })
      end)

      conn =
        get(conn, ~p"/users/settings/calendars/google/callback", %{
          "code" => "auth-code",
          "state" => "expected-state"
        })

      assert redirected_to(conn) == ~p"/users/settings"

      cred = CalendarCredentials.get(user.id, "google")
      assert cred.status == "connected"

      assert {:ok, creds} = CalendarCredentials.decrypt_credentials(cred)
      assert creds["access_token"] == "at-123"
      assert creds["refresh_token"] == "rt-456"
      assert is_integer(creds["expires_at"])
    end

    test "rejects a state mismatch", %{conn: conn, user: user} do
      conn =
        get(conn, ~p"/users/settings/calendars/google/callback", %{
          "code" => "auth-code",
          "state" => "wrong"
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Google"
      assert CalendarCredentials.get(user.id, "google") == nil
    end

    test "handles user denial", %{conn: conn, user: user} do
      conn =
        get(conn, ~p"/users/settings/calendars/google/callback", %{
          "error" => "access_denied"
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert CalendarCredentials.get(user.id, "google") == nil
    end
  end
end
