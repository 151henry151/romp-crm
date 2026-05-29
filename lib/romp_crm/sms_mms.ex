defmodule RompCrm.SmsMms do
  @moduledoc false

  import Ecto.Query

  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobPhoto
  alias RompCrm.Repo
  alias RompCrm.SmsConversations.Message

  @twilio_url_pattern ~r/https:\/\/[^\s\]]+/i

  @doc """
  Body text stored on inbound rows — never blank (MMS includes attachment URLs for later turns).
  """
  def body_for_storage(body_text, params) when is_binary(body_text) and is_map(params) do
    trimmed = String.trim(body_text)

    base =
      if trimmed == "" do
        "(Inbound SMS body empty.)"
      else
        trimmed
      end

    case media_url_suffix_for_storage(params) do
      "" -> base
      suffix -> base <> suffix
    end
  end

  @doc "Twilio `MediaUrlN` values from webhook params."
  def media_urls_from_params(params) when is_map(params) do
    case parse_num_media(params) do
      n when n > 0 ->
        for i <- 0..(n - 1) do
          case params["MediaUrl#{i}"] || params[:"MediaUrl#{i}"] do
            u when is_binary(u) ->
              t = String.trim(u)
              if t != "", do: t, else: nil

            _ ->
              nil
          end
        end
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  @doc """
  Recent Twilio media URLs embedded in stored inbound bodies.

  Not used for orphan attach (would re-attach older MMS to a newly inferred job).
  Kept for tests and possible future "text-only follow-up" tooling.
  """
  def recent_media_urls_from_conversation(business_id, phone_normalized, opts \\ [])
      when is_integer(business_id) and is_binary(phone_normalized) do
    hours = Keyword.get(opts, :within_hours, 72)
    limit = Keyword.get(opts, :limit, 5)
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    from(m in Message,
      where: m.business_id == ^business_id,
      where: m.phone_normalized == ^phone_normalized,
      where: m.direction == "inbound",
      where: m.inserted_at >= ^cutoff,
      order_by: [desc: m.id],
      limit: ^limit,
      select: m.body
    )
    |> Repo.all()
    |> Enum.flat_map(&extract_twilio_media_urls/1)
    |> Enum.uniq()
  end

  @doc """
  When the model did not emit `attach_photo` but we still have MMS URL(s) and can infer a job,
  returns `{:ok, {:photos_saved, job, saved, attempted}}` or `:skip`.
  """
  def maybe_attach_orphan_mms(results, business_id, _phone_normalized, body_text, params, jobs_snapshot)
      when is_list(results) and is_list(jobs_snapshot) do
    if photos_saved_in_results?(results) do
      :skip
    else
      urls = media_urls_from_params(params)

      cond do
        urls == [] ->
          :skip

        not meaningful_inbound_body?(body_text) ->
          :skip

        true ->
          case infer_job_and_work_item(body_text, business_id, jobs_snapshot) do
            {:ok, job_id, work_item_hint} ->
              attach_urls(job_id, business_id, urls, work_item_hint)

            :skip ->
              :skip
          end
      end
    end
  end

  defp photos_saved_in_results?(results) do
    Enum.any?(results, fn
      {:photos_saved, _, _, _} -> true
      _ -> false
    end)
  end

  defp attach_urls(job_id, business_id, urls, work_item_hint) do
    case Jobs.get_job(job_id, business_id) do
      %Job{} = job ->
        wi_id =
          case work_item_hint do
            nil -> nil
            "" -> nil
            hint -> Jobs.find_work_item_id_by_title_substring(job, hint)
          end

        attach_results =
          Enum.map(urls, fn url -> Jobs.add_job_photo_from_url(job, business_id, url, wi_id) end)

        ok_ct = Enum.count(attach_results, &match?({:ok, %JobPhoto{}}, &1))
        skip_ct = Enum.count(attach_results, &match?({:ok, :duplicate_skipped}, &1))

        if ok_ct > 0 or skip_ct == length(urls) do
          {:ok, {:photos_saved, job, ok_ct, length(urls)}}
        else
          {:error, attach_results}
        end

      nil ->
        :skip
    end
  end

  defp meaningful_inbound_body?(body_text) when is_binary(body_text) do
    t = body_text |> String.trim() |> String.downcase()

    t != "" and
      not String.starts_with?(t, "(inbound sms body empty") and
      not String.starts_with?(t, "(inbound sms body empty.")
  end

  defp meaningful_inbound_body?(_), do: false

  # Only match client/work-item names in *this* message — not older thread lines.
  defp infer_job_and_work_item(body_text, business_id, jobs_snapshot) do
    context = body_text |> String.trim() |> String.downcase()

    if context == "" do
      :skip
    else
      job_row =
        jobs_snapshot
        |> Enum.find(fn row ->
          name = row["client_name"] || row[:client_name] || ""

          name = String.downcase(String.trim(to_string(name)))
          name != "" and String.contains?(context, name)
        end)

      case job_row do
        %{"id" => id} when is_integer(id) ->
          {:ok, id, infer_work_item_hint(context, id, business_id)}

        %{id: id} when is_integer(id) ->
          {:ok, id, infer_work_item_hint(context, id, business_id)}

        _ ->
          :skip
      end
    end
  end

  defp infer_work_item_hint(context, job_id, business_id) do
    case Jobs.get_job(job_id, business_id) do
      %Job{work_items: items} when is_list(items) ->
        items
        |> Enum.find_value(fn wi ->
          title = wi.title |> to_string() |> String.trim() |> String.downcase()

          if title != "" and String.contains?(context, title), do: wi.title, else: nil
        end)

      _ ->
        nil
    end
  end

  def extract_twilio_media_urls(text) when is_binary(text) do
    @twilio_url_pattern
    |> Regex.scan(text)
    |> Enum.map(fn [u] -> u end)
    |> Enum.filter(&twilio_media_url?/1)
    |> Enum.uniq()
  end

  def extract_twilio_media_urls(_), do: []

  defp twilio_media_url?(url) do
    uri = URI.parse(url)

    uri.scheme == "https" and uri.host in twilio_media_hosts()
  end

  defp twilio_media_hosts do
    ~w(api.twilio.com mms.twilio.com media.twiliocdn.com)
  end

  defp media_url_suffix_for_storage(params) do
    urls = media_urls_from_params(params)

    if urls == [] do
      ""
    else
      lines =
        urls
        |> Enum.with_index(1)
        |> Enum.map_join("", fn {u, ix} -> "\n#{ix}. #{u}" end)

      "\n\n[MMS attachments — #{length(urls)} URL(s) stored for follow-up:]" <> lines
    end
  end

  defp parse_num_media(params) do
    raw = params["NumMedia"] || ""

    case Integer.parse(to_string(raw)) do
      {n, _} -> min(max(n, 0), 10)
      :error -> 0
    end
  end
end
