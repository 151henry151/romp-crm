defmodule RompCrmWeb.PrintReportsControllerTest do
  use RompCrmWeb.ConnCase, async: true

  alias RompCrm.Businesses
  alias RompCrm.JobsFixtures

  describe "POST /users/settings/reports" do
    setup :register_and_log_in_user_with_business

    test "downloads activity PDF for owned workspace", %{conn: conn, user: user} do
      [biz] = Businesses.list_owned_businesses_for_user(user)

      JobsFixtures.job_fixture(%{
        business_id: biz.id,
        client_name: "Report Lead",
        status: :lead
      })

      conn =
        post(conn, ~p"/users/settings/reports", %{
          "report_type" => "activity",
          "from_date" => "2026-07-01",
          "to_date" => "2026-07-31",
          "export_business_ids" => [to_string(biz.id)]
        })

      assert response(conn, 200)
      [ct | _] = get_resp_header(conn, "content-type")
      assert ct =~ "application/pdf"
      [cd | _] = get_resp_header(conn, "content-disposition")
      assert cd =~ "attachment"
      assert cd =~ ".pdf"
      assert String.starts_with?(conn.resp_body, "%PDF")
    end

    test "downloads customer list PDF", %{conn: conn, user: user} do
      [biz] = Businesses.list_owned_businesses_for_user(user)

      conn =
        post(conn, ~p"/users/settings/reports", %{
          "report_type" => "customers",
          "export_business_ids" => [to_string(biz.id)]
        })

      assert response(conn, 200)
      assert String.starts_with?(conn.resp_body, "%PDF")
      [cd | _] = get_resp_header(conn, "content-disposition")
      assert cd =~ "customers"
    end

    test "rejects missing workspace selection", %{conn: conn} do
      conn =
        post(conn, ~p"/users/settings/reports", %{
          "report_type" => "customers",
          "export_business_ids" => []
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "workspace"
    end

    test "rejects invalid report type", %{conn: conn, user: user} do
      [biz] = Businesses.list_owned_businesses_for_user(user)

      conn =
        post(conn, ~p"/users/settings/reports", %{
          "report_type" => "nope",
          "export_business_ids" => [to_string(biz.id)]
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "report"
    end
  end

  describe "POST /users/settings/reports (no owned business)" do
    setup :register_and_log_in_user

    test "redirects with error", %{conn: conn} do
      conn =
        post(conn, ~p"/users/settings/reports", %{
          "report_type" => "customers",
          "export_business_ids" => ["1"]
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "owned"
    end
  end
end
