defmodule RompCrm.Businesses.Notifier do
  @moduledoc false
  import Swoosh.Email

  alias RompCrm.Mailer
  alias RompCrm.Businesses.{Business, BusinessInvitation}
  alias RompCrm.EmailHtml

  defp from_tuple do
    from_name = Application.get_env(:romp_crm, :mail_from_name, "Romp CRM")
    from_address = Application.get_env(:romp_crm, :mail_from_address, "contact@example.com")
    {from_name, from_address}
  end

  defp base_email(recipient) do
    {from_name, from_address} = from_tuple()

    new()
    |> to(recipient)
    |> from({from_name, from_address})
  end

  defp deliver(recipient, subject, text_body, html_inner) when is_binary(html_inner) do
    html = EmailHtml.layout(html_inner)

    email =
      base_email(recipient)
      |> subject(subject)
      |> text_body(text_body)
      |> html_body(html)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_invitation(%BusinessInvitation{} = invitation, %Business{} = business, accept_url) do
    text = """

    ==============================

    You have been invited to collaborate on "#{business.name}" in Romp CRM.

    Open this link while logged in as #{invitation.email} (create an account first if needed):

    #{accept_url}

    This invitation expires in #{RompCrm.Businesses.BusinessInvitation.token_validity_in_days()} days.

    ==============================
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("You're invited to a workspace")),
        EmailHtml.p(
          EmailHtml.escape(
            "You have been invited to collaborate on \"#{business.name}\" in Romp CRM."
          )
        ),
        EmailHtml.p(
          EmailHtml.escape(
            "Open the link below while signed in as #{invitation.email} (create an account first if you need one)."
          )
        ),
        EmailHtml.cta_button(accept_url, "View invitation"),
        EmailHtml.url_fallback(accept_url),
        EmailHtml.muted_p(
          EmailHtml.escape(
            "This invitation expires in #{RompCrm.Businesses.BusinessInvitation.token_validity_in_days()} days."
          )
        )
      ]
      |> Enum.join()

    deliver(invitation.email, "Invitation to #{business.name} on Romp CRM", text, inner)
  end
end
