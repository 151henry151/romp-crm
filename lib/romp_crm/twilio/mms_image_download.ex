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

  defp fetch_one(url) when is_binary(url) do
    account_sid = Application.get_env(:romp_crm, :twilio_account_sid)
    token = Application.get_env(:romp_crm, :twilio_auth_token)

    if is_nil(account_sid) or account_sid == "" or is_nil(token) or token == "" do
      nil
    else
      auth = Base.encode64("#{account_sid}:#{token}")

      case Req.get(String.trim(url),
             headers: [{"authorization", "Basic #{auth}"}],
             receive_timeout: 60_000
           ) do
        {:ok, %{status: 200, body: body, headers: h}} when is_binary(body) ->
          if byte_size(body) <= @max_bytes do
            %{
              media_type: content_type_for_vision(h),
              data: Base.encode64(body)
            }
          else
            nil
          end

        _ ->
          nil
      end
    end
  end

  defp fetch_one(_), do: nil

  defp content_type_for_vision(headers) do
    ct =
      headers
      |> Enum.find_value("image/jpeg", fn
        {"content-type", v} -> header_value(v)
        {"Content-Type", v} -> header_value(v)
        _ -> nil
      end)

    case ct do
      "image/png" -> "image/png"
      "image/gif" -> "image/gif"
      "image/webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  defp header_value(v) when is_binary(v), do: v |> String.split(";") |> List.first() |> String.trim()
  defp header_value([h | _]) when is_binary(h), do: header_value(h)
  defp header_value(_), do: "image/jpeg"
end
