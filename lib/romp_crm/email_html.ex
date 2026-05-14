defmodule RompCrm.EmailHtml do
  @moduledoc false

  import Plug.HTML, only: [html_escape: 1]

  @font "'Inter','Segoe UI',Roboto,'Helvetica Neue',Helvetica,Arial,sans-serif"

  @doc "Absolute URL for the logo image in HTML emails."
  def logo_url do
    Application.get_env(:romp_crm, :email_logo_url) ||
      "https://rompcrm.com/media/romp-crm-logo-main-dark.png"
  end

  @doc "Marketing / product site link for the email footer."
  def brand_base_url do
    Application.get_env(:romp_crm, :email_brand_base_url) ||
      "https://rompcrm.com"
  end

  @doc "Escape text for safe interpolation into HTML."
  def escape(bin) when is_binary(bin), do: html_escape(bin)

  @doc """
  Wraps inner HTML (must already be safe: use `escape/1` for user-controlled strings)
  in a table-based layout aligned with Romp CRM marketing colors.
  """
  def layout(inner_html) when is_binary(inner_html) do
    logo = logo_url() |> html_escape()
    brand = brand_base_url() |> html_escape()

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Romp CRM</title>
    </head>
    <body style="margin:0;padding:0;background-color:#0b1220;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#0b1220;">
      <tr>
        <td align="center" style="padding:28px 16px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background-color:#121c31;border-radius:14px;border:1px solid #253453;">
            <tr>
              <td style="padding:28px 24px 8px;">
                <img src="#{logo}" alt="Romp CRM" width="220" height="auto" style="display:block;max-width:220px;width:100%;height:auto;margin:0 auto 8px;border:0;outline:none;text-decoration:none;" />
              </td>
            </tr>
            <tr>
              <td style="padding:8px 24px 28px;font-family:#{@font};">
                #{inner_html}
              </td>
            </tr>
            <tr>
              <td style="padding:16px 24px 22px;border-top:1px solid #253453;">
                <p style="margin:0;font-size:12px;line-height:1.5;font-family:#{@font};color:#a8b6cf;text-align:center;">
                  <a href="#{brand}" style="color:#7dd3fc;text-decoration:none;font-weight:600;">rompcrm.com</a>
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
    </body>
    </html>
    """
  end

  def h1(title_html) do
    ~s(<h1 style="margin:0 0 16px;font-family:#{@font};font-size:22px;font-weight:700;color:#e6edf8;line-height:1.25;">#{title_html}</h1>)
  end

  def p(content_html) do
    ~s(<p style="margin:0 0 14px;font-family:#{@font};font-size:15px;line-height:1.55;color:#e6edf8;">#{content_html}</p>)
  end

  def muted_p(content_html) do
    ~s(<p style="margin:0 0 14px;font-family:#{@font};font-size:13px;line-height:1.5;color:#a8b6cf;">#{content_html}</p>)
  end

  def cta_button(href, label) when is_binary(href) and is_binary(label) do
    eh = html_escape(href)
    el = html_escape(label)

    """
    <table role="presentation" cellspacing="0" cellpadding="0" style="margin:0 0 18px;">
      <tr>
        <td style="border-radius:10px;background-color:#38bdf8;">
          <a href="#{eh}" style="display:inline-block;padding:12px 22px;font-family:#{@font};font-size:15px;font-weight:600;color:#0b1220;text-decoration:none;">#{el}</a>
        </td>
      </tr>
    </table>
    """
  end

  def url_fallback(url) when is_binary(url) do
    eu = html_escape(url)

    ~s(<p style="margin:0 0 16px;font-size:12px;line-height:1.45;font-family:#{@font};color:#a8b6cf;word-break:break-word;">If the button does not work, copy and paste this link into your browser:<br /><span style="color:#7dd3fc;">#{eu}</span></p>)
  end

  def bullet_list(items) when is_list(items) do
    lis =
      items
      |> Enum.map(fn item ->
        ~s(<li style="margin:0 0 6px;">#{item}</li>)
      end)
      |> Enum.join()

    ~s(<ul style="margin:0 0 16px;padding-left:20px;font-family:#{@font};font-size:14px;line-height:1.5;color:#e6edf8;">#{lis}</ul>)
  end

  @doc "Escape then turn newlines into `<br />` for simple plain-text blocks."
  def multiline_html(text) when is_binary(text) do
    text
    |> html_escape()
    |> String.split("\n")
    |> Enum.intersperse("<br />")
    |> IO.iodata_to_binary()
  end

  def callout(html_inner) do
    ~s(<div style="margin:0 0 18px;padding:14px 16px;border-radius:10px;border:1px solid #253453;background-color:#1a2742;">#{html_inner}</div>)
  end
end
