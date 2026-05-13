defmodule RompCrmWeb.JobPhotoController do
  use RompCrmWeb, :controller

  alias RompCrm.Businesses
  alias RompCrm.EmployeePermissions
  alias RompCrm.Jobs

  def create(conn, %{"job_id" => job_id} = params) do
    user = conn.assigns.current_scope.user
    businesses = Businesses.list_businesses_for_user(user)
    bid = Businesses.resolve_active_business_id(user, businesses, conn.private[:plug_session] || %{})

    caps = EmployeePermissions.for(user, bid)

    if not EmployeePermissions.can_edit_jobs?(caps) do
      conn
      |> put_flash(:error, "You do not have permission to upload photos.")
      |> redirect(to: ~p"/")
    else
      do_upload(conn, bid, job_id, params)
    end
  end

  defp do_upload(conn, business_id, job_id, params) do
    case {Integer.parse(to_string(job_id)), params["photo"]} do
      {{jid, _}, %Plug.Upload{path: path, content_type: ct}} ->
        bytes = File.read!(path)
        wi_id = parse_optional_int(Map.get(params, "job_work_item_id"))

        case Jobs.get_job(jid, business_id) do
          nil ->
            conn
            |> put_flash(:error, "Job not found.")
            |> redirect(to: ~p"/")

          job ->
            case Jobs.add_job_photo(job, business_id, bytes, ct || "image/jpeg", wi_id) do
              {:ok, _} ->
                conn
                |> put_flash(:info, "Photo uploaded.")
                |> redirect(to: ~p"/")

              {:error, reason} ->
                conn
                |> put_flash(:error, "Could not save photo (#{inspect(reason)}).")
                |> redirect(to: ~p"/")
            end
        end

      _ ->
        conn
        |> put_flash(:error, "Choose a photo file to upload.")
        |> redirect(to: ~p"/")
    end
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
