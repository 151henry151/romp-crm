defmodule RompCrmWeb.ChatMediaController do
  use RompCrmWeb, :controller

  alias RompCrm.Businesses
  alias RompCrm.ChatMedia
  alias RompCrm.ClientChats

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    bid = active_business_id(conn, user)

    cond do
      is_nil(bid) ->
        respond_error(conn, :bad_request, "Pick a workspace first.")

      not member?(user, bid) ->
        respond_error(conn, :forbidden, "You do not have access to this workspace.")

      true ->
        do_upload(conn, bid, params)
    end
  end

  defp do_upload(conn, business_id, params) do
    phone =
      (params["phone"] || conn.query_params["phone"] || "")
      |> to_string()
      |> String.trim()
      |> RompCrm.Twilio.Phone.normalize_us()

    case {phone, params["photo"]} do
      {_, %Plug.Upload{path: path, content_type: ct}} ->
        if phone == "" or ClientChats.taken_over?(business_id, phone) do
          bytes = File.read!(path)

          case ChatMedia.store!(business_id, bytes, ct || "image/jpeg") do
            {:ok, %{public_url: url, relative_path: rel}} ->
              respond_success(conn, %{url: url, relative_path: rel})

            {:error, :too_large} ->
              respond_error(conn, :request_entity_too_large, "Photo is too large (max 5 MB).")

            {:error, reason} ->
              respond_error(conn, :unprocessable_entity, "Could not save photo (#{inspect(reason)}).")
          end
        else
          respond_error(conn, :forbidden, "Take over the chat before attaching photos.")
        end

      _ ->
        respond_error(conn, :bad_request, "No photo uploaded.")
    end
  end

  defp member?(user, business_id), do: Businesses.member?(user, business_id)

  defp active_business_id(conn, user) do
    case get_session(conn, :current_business_id) do
      id when is_integer(id) ->
        if Businesses.member?(user, id), do: id, else: fallback_business_id(user)

      _ ->
        fallback_business_id(user)
    end
  end

  defp fallback_business_id(user) do
    case Businesses.list_businesses_for_user(user) do
      [%{id: id} | _] -> id
      _ -> nil
    end
  end

  defp respond_success(conn, payload) when is_map(payload) do
    if xhr?(conn) do
      json(conn, Map.put(payload, :ok, true))
    else
      conn
      |> put_flash(:info, "Photo attached.")
      |> redirect(to: ~p"/chats")
    end
  end

  defp respond_error(conn, status, message) do
    if xhr?(conn) do
      conn
      |> put_status(status)
      |> json(%{ok: false, error: message})
    else
      conn
      |> put_flash(:error, message)
      |> redirect(to: ~p"/chats")
    end
  end

  defp xhr?(conn), do: get_req_header(conn, "x-photo-upload") != []
end
