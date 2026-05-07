defmodule RompCrm.Businesses.Notifier do
  @moduledoc false
  import Swoosh.Email

  alias RompCrm.Mailer
  alias RompCrm.Businesses.{Business, BusinessInvitation}

  defp deliver(recipient, subject, body) do
    from_name = Application.get_env(:romp_crm, :mail_from_name, "Romp CRM")
    from_address = Application.get_env(:romp_crm, :mail_from_address, "contact@example.com")

    email =
      new()
      |> to(recipient)
      |> from({from_name, from_address})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_invitation(%BusinessInvitation{} = invitation, %Business{} = business, accept_url) do
    deliver(invitation.email, "Invitation to #{business.name} on Romp CRM", """

    ==============================

    You have been invited to collaborate on "#{business.name}" in Romp CRM.

    Open this link while logged in as #{invitation.email} (create an account first if needed):

    #{accept_url}

    This invitation expires in #{RompCrm.Businesses.BusinessInvitation.token_validity_in_days()} days.

    ==============================
    """)
  end
end
