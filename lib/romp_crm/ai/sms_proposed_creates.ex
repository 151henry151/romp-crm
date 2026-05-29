defmodule RompCrm.Ai.SmsProposedCreates do
  @moduledoc false

  alias RompCrm.Ai.SmsJobExtractor

  @valid_image_kinds ~w(sms_screenshot email_screenshot handwritten_note none other)

  def valid_image_kind?(kind) when is_binary(kind), do: kind in @valid_image_kinds
  def valid_image_kind?(_), do: false

  def parse_image_kind(nil), do: nil

  def parse_image_kind(kind) when is_binary(kind) do
    k = kind |> String.trim() |> String.downcase()

    if k in @valid_image_kinds, do: k, else: "other"
  end

  def parse_image_kind(_), do: "other"

  def parse_list(list) when is_list(list) do
    list
    |> Enum.map(&parse_one/1)
    |> Enum.reject(&is_nil/1)
  end

  def parse_list(_), do: []

  defp parse_one(%{"job" => job} = map) when is_map(job) do
    urls = collect_urls(map)

    %{
      job_attrs: SmsJobExtractor.normalize_proposed_job_attrs(job),
      attach_media_urls: urls
    }
  end

  defp parse_one(map) when is_map(map) do
    parse_one(%{"job" => map, "attach_media_urls" => Map.get(map, "attach_media_urls")})
  end

  defp parse_one(_), do: nil

  defp collect_urls(map) do
    urls =
      case map["attach_media_urls"] || map["media_urls"] do
        list when is_list(list) ->
          list
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    one =
      case map["attach_media_url"] || map["media_url"] do
        u when is_binary(u) ->
          t = String.trim(u)
          if t != "", do: [t], else: []

        _ ->
          []
      end

    (urls ++ one) |> Enum.uniq()
  end
end
