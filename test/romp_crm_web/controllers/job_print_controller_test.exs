defmodule RompCrmWeb.JobPrintControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.JobsFixtures

  alias RompCrm.Businesses

  setup :register_and_log_in_user_with_business

  test "downloads a PDF for a job in the active workspace", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "Will Nash",
        work_description: "Repair sink"
      })

    conn = get(conn, ~p"/jobs/#{job.id}/print")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "will-nash"
    assert disposition =~ ".pdf"
    assert byte_size(response(conn, 200)) > 0
  end

  test "returns not found flash redirect for missing job", %{conn: conn} do
    conn = get(conn, ~p"/jobs/999999/print")
    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
  end

  test "downloads a PDF without photos when photos=0", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "No Photos Print",
        work_description: "Quick print"
      })

    conn = get(conn, ~p"/jobs/#{job.id}/print?photos=0")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
    assert byte_size(response(conn, 200)) > 0
  end
end
