defmodule RompCrm.ChatMedia do
  @moduledoc """
  Staging for outbound chat MMS images. Files live under
  **`uploads/chat-media/<business_id>/`** (same static root as job photos) so
  Twilio can fetch a public HTTPS `MediaUrl`.
  """

  alias RompCrm.JobUploads
  alias RompCrmWeb.Endpoint

  @max_bytes 5_000_000
  @max_images 4

  def max_images, do: @max_images

  @doc """
  Writes `bytes` and returns `%{relative_path, public_url}` for Twilio + UI.
  """
  def store!(business_id, bytes, content_type)
      when is_integer(business_id) and is_binary(bytes) do
    cond do
      byte_size(bytes) == 0 ->
        {:error, :empty}

      byte_size(bytes) > @max_bytes ->
        {:error, :too_large}

      true ->
        ext = ext_from_content_type(content_type)
        id = Ecto.UUID.generate()
        rel = "uploads/chat-media/#{business_id}/#{id}#{ext}"
        abs = JobUploads.absolute_path(rel)
        :ok = File.mkdir_p(Path.dirname(abs))
        :ok = File.write!(abs, bytes)

        {:ok, %{relative_path: rel, public_url: public_url(rel)}}
    end
  end

  def public_url(relative_path) when is_binary(relative_path) do
    path =
      relative_path
      |> String.trim()
      |> String.trim_leading("/")
      |> then(&("/" <> &1))

    Endpoint.url()
    |> String.trim_trailing("/")
    |> Kernel.<>(Endpoint.path(path))
  end

  defp ext_from_content_type(ct) when is_binary(ct) do
    case ct |> String.split(";") |> List.first() |> String.trim() |> String.downcase() do
      "image/png" -> ".png"
      "image/gif" -> ".gif"
      "image/webp" -> ".webp"
      "image/jpeg" -> ".jpg"
      "image/jpg" -> ".jpg"
      _ -> ".jpg"
    end
  end

  defp ext_from_content_type(_), do: ".jpg"
end
