defmodule RompCrm.EmailHtmlTest do
  use ExUnit.Case, async: true

  alias RompCrm.EmailHtml

  test "layout uses light theme, wordmark, and logo image src" do
    html = EmailHtml.layout("<p>Hello</p>")
    assert html =~ "Hello"
    assert html =~ "<img"
    assert html =~ "rompcrm.com/media/romp-crm-logo-main-dark.png"
    assert html =~ ~s(alt="Romp CRM")
    assert html =~ "Romp CRM"
    assert html =~ "#f3f4f6"
    assert html =~ "#ffffff"
    assert html =~ "#111827"
  end

  test "escape encodes HTML special characters" do
    assert EmailHtml.escape("<script>") =~ "&lt;"
    assert EmailHtml.escape("a & b") =~ "amp;"
  end

  test "cta_button escapes href and label" do
    html = EmailHtml.cta_button("https://example.com/x?a=1&b=2", "Go >")
    assert html =~ "https://example.com/x?a=1&amp;b=2"
    assert html =~ "&gt;"
  end

  test "multiline_html escapes and preserves line breaks" do
    assert EmailHtml.multiline_html("a\nb") =~ "a"
    assert EmailHtml.multiline_html("a\nb") =~ "<br />"
    assert EmailHtml.multiline_html("a\nb") =~ "b"
  end
end
