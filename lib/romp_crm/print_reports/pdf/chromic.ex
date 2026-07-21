defmodule RompCrm.PrintReports.Pdf.Chromic do
  @moduledoc false

  require Logger

  @doc "Render HTML to PDF bytes via ChromicPDF (headless Chromium)."
  def print_html(html) when is_binary(html) do
    try do
      case ChromicPDF.print_to_pdf(
             {:html, html},
             print_to_pdf: %{
               preferCSSPageSize: true,
               displayHeaderFooter: false,
               printBackground: true
             }
           ) do
        {:ok, b64} when is_binary(b64) ->
          case Base.decode64(b64) do
            {:ok, pdf} -> {:ok, pdf}
            :error -> {:error, :invalid_pdf_base64}
          end

        {:ok, other} ->
          {:error, {:unexpected_pdf_result, other}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e in [ChromicPDF.ChromeError, ChromicPDF.Browser.ExecutionError] ->
        Logger.error("ChromicPDF print failed: #{Exception.message(e)}")
        {:error, :pdf_render_failed}

      e ->
        Logger.error("ChromicPDF unexpected error: #{Exception.format(:error, e, __STACKTRACE__)}")
        {:error, :pdf_render_failed}
    end
  end
end
