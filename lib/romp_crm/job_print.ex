defmodule RompCrm.JobPrint do
  @moduledoc """
  Single-job printable PDF: full job details, hours, and embedded photos.
  """

  require Logger

  alias RompCrm.Addresses
  alias RompCrm.Businesses.Business
  alias RompCrm.JobPrint.Html
  alias RompCrm.JobUploads
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo
  alias RompCrm.TimeTracking

  # Keep compact originals; larger files are resized for ChromicPDF.
  @pdf_photo_max_bytes 180_000
  @pdf_photo_max_edge 900

  @doc """
  Load a job for PDF printing in the given workspace.

  Options:

    * `:include_photos` — when `false`, skip embedding job photos (default `true`)

  Returns `{:ok, report}` or `{:error, :not_found}`.
  """
  def build_job_report(job_id, business_id, opts \\ [])
      when is_integer(job_id) and is_integer(business_id) and is_list(opts) do
    include_photos? = Keyword.get(opts, :include_photos, true)

    case Jobs.get_job(job_id, business_id) do
      nil ->
        {:error, :not_found}

      %Job{} = job ->
        time_entries = TimeTracking.list_time_entries_for_job(job.id, business_id)
        total_minutes = TimeTracking.total_minutes_for_job(job.id, business_id)
        business = Repo.get(Business, business_id)

        photos =
          if include_photos? do
            embed_photos(job)
          else
            []
          end

        {:ok,
         %{
           job: job,
           business_name: (business && business.name) || "Workspace",
           service_address: Addresses.format_service(job),
           billing_address: Addresses.format_billing(job),
           work_items: job.work_items || [],
           materials: Jobs.materials_combined(job),
           time_entries: time_entries,
           total_minutes: total_minutes,
           photos: photos
         }}
    end
  end

  @doc """
  Render a job report to PDF bytes via the configured print adapter.

  Returns `{:ok, pdf_binary, filename}`.
  """
  def render_pdf(report, opts \\ []) when is_map(report) do
    generated_at = Keyword.get(opts, :generated_at, DateTime.utc_now()) |> DateTime.truncate(:second)
    html = Html.job_document(report, generated_at)
    adapter = Application.get_env(:romp_crm, :print_reports_pdf_adapter, RompCrm.PrintReports.Pdf.Chromic)

    with {:ok, pdf} <- adapter.print_html(html) do
      {:ok, pdf, filename_for(report.job, generated_at)}
    end
  end

  @doc false
  def prepare_photo_for_pdf(abs_path, content_type)
      when is_binary(abs_path) and is_binary(content_type) do
    bytes = File.read!(abs_path)
    ct = content_type || guess_content_type(abs_path)

    cond do
      not String.starts_with?(ct, "image/") ->
        {ct, bytes}

      byte_size(bytes) <= @pdf_photo_max_bytes and ct == "image/jpeg" ->
        {ct, bytes}

      true ->
        case downscale_to_jpeg(abs_path) do
          {:ok, jpeg} when byte_size(jpeg) < byte_size(bytes) or ct != "image/jpeg" ->
            {"image/jpeg", jpeg}

          {:ok, jpeg} ->
            {"image/jpeg", jpeg}

          :error ->
            {ct, bytes}
        end
    end
  end

  defp embed_photos(%Job{} = job) do
    (job.photos || [])
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {photo, idx} ->
      abs = JobUploads.absolute_path(photo.relative_path)

      if File.regular?(abs) do
        ct = photo.content_type || guess_content_type(photo.relative_path)

        if String.starts_with?(ct, "image/") do
          {out_ct, bytes} = prepare_photo_for_pdf(abs, ct)

          [
            %{
              id: photo.id,
              index: idx,
              content_type: out_ct,
              data_uri: "data:#{out_ct};base64,#{Base.encode64(bytes)}",
              work_item_id: photo.job_work_item_id
            }
          ]
        else
          []
        end
      else
        []
      end
    end)
  end

  defp downscale_to_jpeg(abs_path) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "romp-job-print-#{System.unique_integer([:positive])}.jpg"
      )

    args = [
      abs_path,
      "-auto-orient",
      "-resize",
      "#{@pdf_photo_max_edge}x#{@pdf_photo_max_edge}>",
      "-quality",
      "72",
      tmp
    ]

    try do
      case System.cmd("convert", args, stderr_to_stdout: true) do
        {_, 0} ->
          if File.regular?(tmp) do
            jpeg = File.read!(tmp)
            File.rm(tmp)
            {:ok, jpeg}
          else
            :error
          end

        {out, code} ->
          Logger.warning("JobPrint ImageMagick convert failed (#{code}): #{String.slice(out, 0, 200)}")
          File.rm(tmp)
          :error
      end
    rescue
      e ->
        Logger.warning("JobPrint ImageMagick convert error: #{Exception.message(e)}")
        File.rm(tmp)
        :error
    end
  end

  defp guess_content_type(path) when is_binary(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  defp filename_for(%Job{} = job, %DateTime{} = at) do
    slug =
      job.client_name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "job"
        s -> String.slice(s, 0, 40)
      end

    "job-#{job.id}-#{slug}-#{Calendar.strftime(at, "%Y-%m-%d")}.pdf"
  end
end
