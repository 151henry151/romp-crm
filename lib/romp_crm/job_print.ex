defmodule RompCrm.JobPrint do
  @moduledoc """
  Single-job printable PDF: full job details, hours, and embedded photos.
  """

  alias RompCrm.Addresses
  alias RompCrm.Businesses.Business
  alias RompCrm.JobPrint.Html
  alias RompCrm.JobUploads
  alias RompCrm.Jobs
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo
  alias RompCrm.TimeTracking

  @doc """
  Load a job for PDF printing in the given workspace.

  Returns `{:ok, report}` or `{:error, :not_found}`.
  """
  def build_job_report(job_id, business_id)
      when is_integer(job_id) and is_integer(business_id) do
    case Jobs.get_job(job_id, business_id) do
      nil ->
        {:error, :not_found}

      %Job{} = job ->
        time_entries = TimeTracking.list_time_entries_for_job(job.id, business_id)
        total_minutes = TimeTracking.total_minutes_for_job(job.id, business_id)
        business = Repo.get(Business, business_id)

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
           photos: embed_photos(job)
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

  defp embed_photos(%Job{} = job) do
    (job.photos || [])
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {photo, idx} ->
      abs = JobUploads.absolute_path(photo.relative_path)

      if File.regular?(abs) do
        bytes = File.read!(abs)
        ct = photo.content_type || guess_content_type(photo.relative_path)

        if String.starts_with?(ct, "image/") do
          [
            %{
              id: photo.id,
              index: idx,
              content_type: ct,
              data_uri: "data:#{ct};base64,#{Base.encode64(bytes)}",
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
