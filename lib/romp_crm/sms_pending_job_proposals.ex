defmodule RompCrm.SmsPendingJobProposals do
  @moduledoc """
  Stores AI-proposed job creates from MMS screenshots/notes until the contractor confirms via SMS.
  """

  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo
  alias RompCrm.SmsPendingJobProposals.Pending

  @confirm_re ~r/^(yes|y|confirm|confirmed|ok|okay|create|create them|looks good|go ahead|do it|approve|approved)(\s|$)/i

  @doc "True when the inbound SMS is a short confirmation to apply pending proposals."
  def confirmation_message?(body) when is_binary(body) do
    t = String.trim(body)
    t != "" and String.match?(t, @confirm_re)
  end

  def confirmation_message?(_), do: false

  @doc """
  Replace any pending row for this phone with `proposals` (list of
  `%{job_attrs: map, attach_media_urls: [url]}`).
  """
  def store!(business_id, user_id, phone_normalized, image_kind, proposals)
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) and
             is_list(proposals) do
    encoded = Jason.encode!(encode_proposals(proposals))

    attrs = %{
      business_id: business_id,
      user_id: user_id,
      phone_normalized: phone_normalized,
      image_kind: image_kind,
      proposals_json: encoded
    }

    case Repo.get_by(Pending, business_id: business_id, phone_normalized: phone_normalized) do
      nil ->
        %Pending{} |> Pending.changeset(attrs) |> Repo.insert!()

      row ->
        row |> Pending.changeset(attrs) |> Repo.update!()
    end
  end

  @doc "Create jobs and attach MMS URLs; clears pending row. Returns `{:ok, results}` or `:none`."
  def apply_pending(business_id, user_id, phone_normalized)
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) do
    case Repo.get_by(Pending, business_id: business_id, phone_normalized: phone_normalized) do
      nil ->
        :none

      %Pending{proposals_json: json, user_id: ^user_id} = row ->
        proposals = decode_proposals(json)
        results = apply_proposals_list(proposals, business_id)
        Repo.delete!(row)
        {:ok, results}

      %Pending{} ->
        {:error, :wrong_user}
    end
  end

  defp apply_proposals_list(proposals, business_id) do
    Enum.flat_map(proposals, fn %{job_attrs: attrs, attach_media_urls: urls} ->
      attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("business_id", business_id)

      case Jobs.create_job(attrs) do
        {:ok, %Job{} = job} ->
          job = Jobs.get_job!(job.id, business_id)

          photo_results =
            Enum.map(urls, fn url -> Jobs.add_job_photo_from_url(job, business_id, url) end)

          saved =
            Enum.count(photo_results, fn
              {:ok, %RompCrm.Jobs.JobPhoto{}} -> true
              {:ok, :duplicate_skipped} -> true
              _ -> false
            end)

          [
            {:created, job, RompCrm.BusinessAuditLogs.Detail.changes_for_job_created(job)},
            {:photos_saved, job, saved, length(urls)}
          ]

        {:error, _} ->
          [{:error, :create_failed}]
      end
    end)
  end

  defp encode_proposals(proposals) do
    Enum.map(proposals, fn %{job_attrs: attrs, attach_media_urls: urls} ->
      %{
        "job" => Map.new(attrs, fn {k, v} -> {to_string(k), encode_val(v)} end),
        "attach_media_urls" => urls
      }
    end)
  end

  defp encode_val(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_val(v), do: v

  defp decode_proposals(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> RompCrm.Ai.SmsProposedCreates.parse_list(list)
      _ -> []
    end
  end
end
