defmodule RompCrm.PrintReports.Pdf.Stub do
  @moduledoc false

  @doc "Return a tiny valid-looking PDF embedding a hash of the HTML (tests only)."
  def print_html(html) when is_binary(html) do
    digest = :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)

    pdf =
      "%PDF-1.4\n" <>
        "1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n" <>
        "2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n" <>
        "3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj\n" <>
        "xref\n0 4\n0000000000 65535 f \ntrailer<< /Size 4 /Root 1 0 R /Info << /Title (#{digest}) >> >>\n" <>
        "startxref\n0\n%%EOF\n"

    {:ok, pdf}
  end
end
