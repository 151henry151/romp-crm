defmodule RompCrmWeb.JobPhotoController do
  use RompCrmWeb, :controller

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.JobPhotoExport
  alias RompCrm.JobUploads
  alias RompCrm.Jobs

  def create(conn, %{"job_id" => job_id} = params) do
    user = conn.assigns.current_scope.user
    bid = active_business_id(conn, user)

    caps = EmployeePermissions.for(user, bid)

    if not EmployeePermissions.can_edit_jobs?(caps) do
      respond_error(conn, :forbidden, "You do not have permission to upload photos.")
    else
      do_upload(conn, user, bid, job_id, params)
    end
  end

  def download(conn, %{"job_id" => job_id, "photo_id" => photo_id}) do
    user = conn.assigns.current_scope.user
    bid = active_business_id(conn, user)

    with {:ok, _job, photo} <- fetch_job_photo(job_id, photo_id, bid) do
      abs = JobUploads.absolute_path(photo.relative_path)

      if File.regular?(abs) do
        filename = JobPhotoExport.photo_download_filename(photo)

        conn
        |> put_resp_content_type(photo.content_type || "application/octet-stream")
        |> put_resp_header("content-disposition", content_disposition_attachment(filename))
        |> send_file(200, abs)
      else
        conn
        |> put_flash(:error, "Photo file is missing on the server.")
        |> redirect(to: ~p"/")
      end
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> text("Not found")

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("Bad request")
    end
  end

  def download_all(conn, %{"job_id" => job_id}) do
    bid = active_business_id(conn, conn.assigns.current_scope.user)

    with {:ok, job} <- fetch_job(job_id, bid),
         {:ok, body} <- JobPhotoExport.build_job_photos_zip(job) do
      filename = JobPhotoExport.job_zip_filename(job)

      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", content_disposition_attachment(filename))
      |> send_resp(200, body)
    else
      {:error, :no_photos} ->
        conn
        |> put_flash(:error, "This job has no photos to download.")
        |> redirect(to: ~p"/")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> text("Not found")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not build photo download. (#{inspect(reason)})")
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("Bad request")
    end
  end

  defp do_upload(conn, user, business_id, job_id, params) do
    case {Integer.parse(to_string(job_id)), params["photo"]} do
      {{jid, _}, %Plug.Upload{path: path, content_type: ct}} ->
        bytes = File.read!(path)
        wi_id = parse_optional_int(Map.get(params, "job_work_item_id"))

        case Jobs.get_job(jid, business_id) do
          nil ->
            respond_error(conn, :not_found, "Job not found.")

          job ->
            case Jobs.add_job_photo(job, business_id, bytes, ct || "image/jpeg", wi_id) do
              {:ok, _photo} ->
                BusinessAuditLogs.record(%{
                  business_id: business_id,
                  actor_user_id: user.id,
                  source: "web",
                  action: "jobs.photos.upload",
                  entity_type: "jobs",
                  entity_id: jid,
                  metadata: %{count: 1}
                })

                respond_success(conn, "Photo uploaded.")

              {:error, reason} ->
                respond_error(conn, :unprocessable_entity, "Could not save photo (#{inspect(reason)}).")
            end
        end

      _ ->
        respond_error(conn, :bad_request, "Choose a photo file to upload.")
    end
  end

  defp active_business_id(conn, user) do
    businesses = Businesses.list_businesses_for_user(user)
    Businesses.resolve_active_business_id(user, businesses, conn.private[:plug_session] || %{})
  end

  defp fetch_job_photo(job_id, photo_id, bid) do
    with {:ok, job} <- fetch_job(job_id, bid),
         {:ok, pid} <- parse_id(photo_id),
         photo when not is_nil(photo) <- Enum.find(job.photos || [], &(&1.id == pid)) do
      {:ok, job, photo}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_job(job_id, bid) do
    with {:ok, jid} <- parse_id(job_id),
         job when not is_nil(job) <- Jobs.get_job(jid, bid) do
      {:ok, job}
    else
      _ -> {:error, :not_found}
    end
  end

  defp parse_id(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> {:ok, n}
      :error -> :error
    end
  end

  defp parse_id(v) when is_integer(v), do: {:ok, v}
  defp parse_id(_), do: :error

  defp content_disposition_attachment(filename) when is_binary(filename) do
    safe = String.replace(filename, "\"", "")
    ~s(attachment; filename="#{safe}")
  end

  defp respond_success(conn, message) do
    if json_request?(conn) do
      json(conn, %{ok: true})
    else
      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/")
    end
  end

  defp respond_error(conn, status, message) do
    if json_request?(conn) do
      conn
      |> put_status(status)
      |> json(%{ok: false, error: message})
    else
      conn
      |> put_flash(:error, message)
      |> redirect(to: ~p"/")
    end
  end

  defp json_request?(conn) do
    "1" in get_req_header(conn, "x-photo-upload") or
      conn.params["_format"] == "json" or
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json"))
  end

  defp parse_optional_int(nil), do: nil
  defp parse_optional_int(""), do: nil

  defp parse_optional_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_optional_int(v) when is_integer(v), do: v
end
