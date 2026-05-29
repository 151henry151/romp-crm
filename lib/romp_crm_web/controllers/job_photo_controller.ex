defmodule RompCrmWeb.JobPhotoController do
  use RompCrmWeb, :controller

  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs

  def create(conn, %{"job_id" => job_id} = params) do
    user = conn.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, conn.private[:plug_session] || %{})

    caps = EmployeePermissions.for(user, bid)

    if not EmployeePermissions.can_edit_jobs?(caps) do
      respond_error(conn, :forbidden, "You do not have permission to upload photos.")
    else
      do_upload(conn, user, bid, job_id, params)
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
