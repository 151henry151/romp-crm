defmodule RompCrm.JobPhotoExport do
  @moduledoc false

  import Ecto.Query

  alias RompCrm.JobUploads
  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobPhoto
  alias RompCrm.Repo

  @doc """
  ZIP of all photos for selected owner business ids.
  One directory per job: `job-{id} - {client_name}/`.
  """
  def build_all_photos_zip(business_ids) when is_list(business_ids) do
    jobs = list_jobs_with_photos(business_ids)

    if jobs == [] do
      {:error, :no_photos}
    else
      specs =
        Enum.flat_map(jobs, fn job ->
          zip_specs_for_photos(job.photos || [], job_folder_name(job))
        end)

      create_zip(specs)
    end
  end

  @doc "ZIP of all photos on one job (files inside a job folder)."
  def build_job_photos_zip(%Job{} = job) do
    photos = job.photos || []

    if photos == [] do
      {:error, :no_photos}
    else
      specs = zip_specs_for_photos(photos, job_folder_name(job))
      create_zip(specs)
    end
  end

  @doc "Suggested attachment filename for a single photo download."
  def photo_download_filename(%JobPhoto{} = photo) do
    base = Path.basename(photo.relative_path)
    "job-photo-#{photo.id}-#{base}"
  end

  @doc "Suggested ZIP filename for one job's photos."
  def job_zip_filename(%Job{} = job) do
    "job-#{job.id}-photos-#{Date.utc_today()}.zip"
  end

  @doc "Suggested ZIP filename for a bulk photo export."
  def bulk_zip_filename do
    "romp-crm-job-photos-#{Date.utc_today()}.zip"
  end

  defp list_jobs_with_photos(business_ids) do
    if business_ids == [] do
      []
    else
      Repo.all(
        from j in Job,
          where: j.business_id in ^business_ids,
          order_by: [asc: j.business_id, asc: j.id],
          preload: [photos: ^photos_preload_query()]
      )
      |> Enum.filter(fn j -> (j.photos || []) != [] end)
    end
  end

  defp photos_preload_query do
    from p in JobPhoto, order_by: [asc: p.sort_order, asc: p.id]
  end

  defp zip_specs_for_photos(photos, folder) when is_list(photos) and is_binary(folder) do
    photos
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {photo, idx} ->
      case photo_file_spec(photo, folder, idx) do
        nil -> []
        spec -> [spec]
      end
    end)
  end

  defp photo_file_spec(%JobPhoto{} = photo, folder, idx) do
    abs = JobUploads.absolute_path(photo.relative_path)

    if File.regular?(abs) do
      zip_name = zip_entry_path(folder, photo_zip_entry_name(photo, idx))
      {String.to_charlist(zip_name), File.read!(abs)}
    end
  end

  defp zip_entry_path(folder, entry) do
    folder <> "/" <> entry
  end

  defp photo_zip_entry_name(%JobPhoto{} = photo, idx) do
    ext = Path.extname(photo.relative_path)

    ext =
      if ext == "" do
        case photo.content_type do
          "image/png" -> ".png"
          "image/webp" -> ".webp"
          "image/gif" -> ".gif"
          _ -> ".jpg"
        end
      else
        ext
      end

    String.pad_leading(to_string(idx), 3, "0") <> "-photo-#{photo.id}" <> ext
  end

  defp job_folder_name(%Job{} = job) do
    "job-#{job.id} - #{sanitize_label(job.client_name)}"
  end

  defp sanitize_label(nil), do: "Untitled"

  defp sanitize_label(name) when is_binary(name) do
    cleaned =
      name
      |> String.replace(~r/[\/\\:*?"<>|]/, "")
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    if cleaned == "", do: "Untitled", else: String.slice(cleaned, 0, 60)
  end

  defp create_zip(specs) when is_list(specs) do
    if specs == [] do
      {:error, :no_photos}
    else
      tmp = Path.join(System.tmp_dir!(), "romp-crm-photos-#{System.unique_integer([:positive])}.zip")
      cl_tmp = String.to_charlist(tmp)

      try do
        case :zip.create(cl_tmp, specs, []) do
          {:ok, _} ->
            {:ok, File.read!(tmp)}

          {:error, reason} ->
            {:error, {:zip_failed, reason}}
        end
      after
        _ = File.rm(tmp)
      end
    end
  end
end
