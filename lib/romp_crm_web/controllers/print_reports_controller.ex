defmodule RompCrmWeb.PrintReportsController do
  use RompCrmWeb, :controller

  alias RompCrm.PrintReports

  import RompCrmWeb.UserAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_mode

  def download(conn, params) do
    user = conn.assigns.current_scope.user

    with {:ok, type} <- PrintReports.normalize_report_type(params),
         {:ok, business_ids} <- PrintReports.normalize_export_business_ids(user, params),
         {:ok, report, opts} <- build_report(type, business_ids, params),
         {:ok, pdf, filename} <- PrintReports.render_pdf(type, report, opts) do
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, pdf)
    else
      {:error, :invalid_report_type} ->
        conn
        |> put_flash(:error, "Pick a report type: Activity or Customer list.")
        |> redirect(to: ~p"/users/settings")

      {:error, :invalid_date_range} ->
        conn
        |> put_flash(:error, "Activity reports need a valid from/to date range.")
        |> redirect(to: ~p"/users/settings")

      {:error, :no_business_selected} ->
        conn
        |> put_flash(:error, "Pick a workspace (owners only).")
        |> redirect(to: ~p"/users/settings")

      {:error, :no_owned_businesses} ->
        conn
        |> put_flash(:error, "Nothing to download—create an owned workspace first.")
        |> redirect(to: ~p"/users/settings")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not build the PDF. (#{inspect(reason)})")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp build_report(:activity, business_ids, params) do
    with {:ok, from_date, to_date} <- PrintReports.normalize_date_range(params) do
      report = PrintReports.build_activity_report(business_ids, from_date, to_date)

      {:ok, report,
       [
         from_date: from_date,
         to_date: to_date,
         generated_at: DateTime.utc_now()
       ]}
    end
  end

  defp build_report(:customers, business_ids, _params) do
    report = PrintReports.build_customer_list(business_ids)
    {:ok, report, [generated_at: DateTime.utc_now()]}
  end
end
