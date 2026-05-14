defmodule RompCrmWeb.UserSettingsControllerTest do
  use RompCrmWeb.ConnCase, async: false

  alias RompCrm.Accounts
  alias RompCrm.Businesses
  alias RompCrm.Repo
  import RompCrm.AccountsFixtures

  setup :register_and_log_in_user

  describe "GET /users/settings" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ "Settings"
      assert response =~ "Data export"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "redirects if user is not in sudo mode", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must re-authenticate to access this page."
    end
  end

  describe "PUT /users/settings (change password form)" do
    test "updates the user password and resets tokens", %{conn: conn, user: user} do
      new_password_conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_password",
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_password",
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(old_password_conn, 200)
      assert response =~ "Settings"
      assert response =~ "should be at least 12 character(s)"
      assert response =~ "does not match password"

      assert get_session(old_password_conn, :user_token) == get_session(conn, :user_token)
    end
  end

  describe "PUT /users/settings (change email form)" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_email",
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "A link to confirm your email"

      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Settings"
      assert response =~ "must have the @ sign and no spaces"
    end
  end

  describe "GET /users/settings/confirm-email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, ~p"/users/settings/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email changed successfully"

      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, ~p"/users/settings/confirm-email/#{token}")

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/settings/confirm-email/oops")
      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/users/settings/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "PUT /users/settings (cancel subscription)" do
    test "returns error flash when hosted paywall is off", %{conn: conn} do
      conn = put(conn, ~p"/users/settings", %{"action" => "cancel_subscription"})

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "no active hosted subscription"
    end

    test "shows cancel subscription button when paywall on and PayPal subscription stored", %{
      conn: conn,
      user: user
    } do
      Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

      on_exit(fn ->
        Application.put_env(:romp_crm, :subscription_paywall_enabled, false)
      end)

      {:ok, _} =
        Repo.update(
          Ecto.Changeset.change(user,
            subscription_status: "active",
            paypal_subscription_id: "I-BUTTON"
          )
        )

      conn = get(conn, ~p"/users/settings")
      html = html_response(conn, 200)
      assert html =~ "Cancel subscription"
      assert html =~ "cancel_subscription"
    end

    test "handles PayPal API failure without clearing subscription", %{conn: conn, user: user} do
      Application.put_env(:romp_crm, :subscription_paywall_enabled, true)

      on_exit(fn ->
        Application.put_env(:romp_crm, :subscription_paywall_enabled, false)
      end)

      {:ok, _} =
        Repo.update(
          Ecto.Changeset.change(user,
            subscription_status: "active",
            paypal_subscription_id: "I-NOCANCEL"
          )
        )

      conn = put(conn, ~p"/users/settings", %{"action" => "cancel_subscription"})

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "PayPal could not cancel"

      updated = Repo.get!(RompCrm.Accounts.User, user.id)
      assert updated.subscription_status == "active"
      assert updated.paypal_subscription_id == "I-NOCANCEL"
    end
  end

  describe "PUT /users/settings (data export)" do
    setup :register_and_log_in_user_with_business

    test "saves scheduled export", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_data_export_schedule",
          "user" => %{"data_export_schedule" => "daily"}
        })

      assert redirected_to(conn) == ~p"/users/settings"
      updated = Repo.get!(RompCrm.Accounts.User, user.id)
      assert updated.data_export_schedule == "daily"
      assert %DateTime{} = updated.data_export_next_run_at
    end

    test "email export shows flash listing selected CSV names", %{conn: conn, user: user} do
      [biz] = Businesses.list_owned_businesses_for_user(user)

      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_email_now",
          "export_kinds" => ["jobs", "employees"],
          "export_business_ids" => [to_string(biz.id)]
        })

      assert redirected_to(conn) == ~p"/users/settings"
      info = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert info =~ "jobs.csv"
      assert info =~ "employees.csv"
      assert info =~ "1 workspace"
    end

    test "email export with no kinds selected shows error", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_email_now",
          "export_kinds" => []
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Choose at least one"
    end

    test "email export with export_kinds omitted shows error", %{conn: conn} do
      conn = put(conn, ~p"/users/settings", %{"action" => "export_email_now"})

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Choose at least one"
    end

    test "email export with no workspace selected shows error", %{conn: conn, user: user} do
      [_] = Businesses.list_owned_businesses_for_user(user)

      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_email_now",
          "export_kinds" => ["jobs"],
          "export_business_ids" => []
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Choose at least one workspace"
    end

    test "email export with export_business_ids omitted shows workspace error", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_email_now",
          "export_kinds" => ["jobs"]
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Choose at least one workspace"
    end

    test "download single selection returns CSV attachment", %{conn: conn, user: user} do
      [biz] = Businesses.list_owned_businesses_for_user(user)

      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_download",
          "export_kinds" => ["jobs"],
          "export_business_ids" => [to_string(biz.id)]
        })

      assert response(conn, 200)
      [ct | _] = get_resp_header(conn, "content-type")
      assert ct =~ "text/csv"
      [cd | _] = get_resp_header(conn, "content-disposition")
      assert cd =~ "jobs.csv"
      assert conn.resp_body =~ "business_id"
    end

    test "download multiple selections returns zip attachment", %{conn: conn, user: user} do
      [biz] = Businesses.list_owned_businesses_for_user(user)

      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_download",
          "export_kinds" => ["jobs", "employees"],
          "export_business_ids" => [to_string(biz.id)]
        })

      assert response(conn, 200)
      [ct | _] = get_resp_header(conn, "content-type")
      assert ct =~ "application/zip"
      assert binary_part(conn.resp_body, 0, 2) == "PK"
    end
  end

  describe "PUT /users/settings (data export download, no owned business)" do
    setup :register_and_log_in_user

    test "redirects with error when user owns no businesses", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_download",
          "export_kinds" => ["jobs"]
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "nothing to download"
    end
  end

  describe "PUT /users/settings (data export email, no owned business)" do
    setup :register_and_log_in_user

    test "redirects with error when user owns no businesses", %{conn: conn} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "export_email_now",
          "export_kinds" => ["jobs"]
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "nothing to export"
    end
  end

  describe "PUT /users/settings (update profile)" do
    test "stores sms reminder prefs from checkboxes and hour select", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_profile",
          "user" => %{
            "sms_reminders_enabled" => "true",
            "sms_reminder_send_hour_utc" => "9",
            "sms_reminder_offsets" => ["7", "1", "0"]
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"

      refreshed = Repo.get!(Accounts.User, user.id)
      prefs = Jason.decode!(refreshed.sms_reminder_prefs_json)
      assert prefs["send_hour_utc"] == 9
      assert prefs["job_offsets"] == [7, 1, 0]
      assert refreshed.sms_reminders_enabled == true
    end

    test "defaults job_offsets when none selected but hour is sent", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/users/settings", %{
          "action" => "update_profile",
          "user" => %{"sms_reminder_send_hour_utc" => "14"}
        })

      assert redirected_to(conn) == ~p"/users/settings"
      refreshed = Repo.get!(Accounts.User, user.id)
      prefs = Jason.decode!(refreshed.sms_reminder_prefs_json)
      assert prefs["send_hour_utc"] == 14
      assert prefs["job_offsets"] == [1, 0]
    end
  end
end
