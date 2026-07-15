defmodule RompCrm.Twilio.MmsImageDownload do
  @moduledoc false

  @max_images 4
  @max_bytes 5_000_000

  @doc """
  Downloads Twilio MMS URLs for Claude vision. Returns a list of
  `%{media_type: "image/jpeg", data: base64}` (skips failures).
  """
  def fetch_for_vision(urls) when is_list(urls) do
    urls
    |> Enum.take(@max_images)
    |> Enum.map(&fetch_one/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Resolves the Anthropic vision `media_type` from image bytes first (magic), then
  the HTTP Content-Type. Twilio sometimes labels JPEGs as `image/png`.
  """
  def media_type_for_body(body, content_type_header)
      when is_binary(body) and is_binary(content_type_header) do
    case sniff_media_type(body) do
      nil -> normalize_content_type(content_type_header)
      mt -> mt
    end
  end

  defp fetch_one(url) when is_binary(url) do
    url = String.trim(url)

    case read_local_chat_media(url) do
      {:ok, body, media_type} ->
        if byte_size(body) <= @max_bytes do
          %{media_type: media_type, data: Base.encode64(body)}
        else
          nil
        end

      :not_local ->
        fetch_remote(url)
    end
  end

  defp fetch_one(_), do: nil

  defp read_local_chat_media(url) do
    path =
      case URI.parse(url) do
        %URI{path: path} when is_binary(path) -> path
        _ -> url
      end

    case Regex.run(~r{/uploads/chat-media/(.+)$}, path) do
      [_, rest] ->
        rel = "uploads/chat-media/" <> rest
        abs = RompCrm.JobUploads.absolute_path(rel)

        if File.regular?(abs) do
          body = File.read!(abs)
          {:ok, body, media_type_for_body(body, "application/octet-stream")}
        else
          :not_local
        end

      _ ->
        :not_local
    end
  end

  defp fetch_remote(url) do
    account_sid = Application.get_env(:romp_crm, :twilio_account_sid)
    token = Application.get_env(:romp_crm, :twilio_auth_token)

    headers =
      if account_sid not in [nil, ""] and token not in [nil, ""] do
        [{"authorization", "Basic #{Base.encode64("#{account_sid}:#{token}")}"}]
      else
        []
      end

    case Req.get(url, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body, headers: h}} when is_binary(body) ->
        if byte_size(body) <= @max_bytes do
          %{
            media_type: media_type_for_body(body, content_type_from_headers(h)),
            data: Base.encode64(body)
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp content_type_from_headers(headers) do
    headers
    |> Enum.find_value("image/jpeg", fn
      {"content-type", v} -> header_value(v)
      {"Content-Type", v} -> header_value(v)
      _ -> nil
    end)
  end

  defp sniff_media_type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  defp sniff_media_type(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: "image/png"
  defp sniff_media_type(<<"GIF87a", _::binary>>), do: "image/gif"
  defp sniff_media_type(<<"GIF89a", _::binary>>), do: "image/gif"
  defp sniff_media_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp sniff_media_type(_), do: nil

  defp normalize_content_type(ct) do
    case header_value(ct) do
      "image/png" -> "image/png"
      "image/gif" -> "image/gif"
      "image/webp" -> "image/webp"
      "image/jpeg" -> "image/jpeg"
      "image/jpg" -> "image/jpeg"
      _ -> "image/jpeg"
    end
  end

  defp header_value(v) when is_binary(v), do: v |> String.split(";") |> List.first() |> String.trim()
  defp header_value([h | _]) when is_binary(h), do: header_value(h)
  defp header_value(_), do: "image/jpeg"
end
