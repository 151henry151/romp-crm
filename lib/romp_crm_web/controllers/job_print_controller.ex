defmodule RompCrmWeb.JobPrintController do
  use RompCrmWeb, :controller

  alias RompCrm.Businesses
  alias RompCrm.JobPrint

  def download(conn, %{"job_id" => job_id} = params) do
    user = conn.assigns.current_scope.user
    bid = active_business_id(conn, user)

    with {:ok, jid} <- parse_id(job_id),
         {:ok, report} <- JobPrint.build_job_report(jid, bid, include_photos: include_photos?(params)),
         {:ok, pdf, filename} <- JobPrint.render_pdf(report) do
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", content_disposition_attachment(filename))
      |> send_resp(200, pdf)
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Job not found.")
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not build the job PDF. (#{inspect(reason)})")
        |> redirect(to: ~p"/")
    end
  end

  defp include_photos?(params) when is_map(params) do
    case Map.get(params, "photos") do
      v when v in ["0", "false", "no", "off"] -> false
      _ -> true
    end
  end

  defp active_business_id(conn, user) do
    businesses = Businesses.list_businesses_for_user(user)
    Businesses.resolve_active_business_id(user, businesses, conn.private[:plug_session] || %{})
  end

  defp parse_id(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> {:ok, n}
      :error -> {:error, :not_found}
    end
  end

  defp parse_id(v) when is_integer(v), do: {:ok, v}
  defp parse_id(_), do: {:error, :not_found}

  defp content_disposition_attachment(filename) when is_binary(filename) do
    safe = String.replace(filename, "\"", "")
    ~s(attachment; filename="#{safe}")
  end
end
