defmodule RompCrm.Accounts.UserNotifier do
  import Swoosh.Email

  alias RompCrm.Mailer
  alias RompCrm.Accounts.User

  # Delivers the email using the application mailer.
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

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Sends CSV attachments (jobs, employees, time log, SMS interaction log) for **owner** businesses only.
  """
  def deliver_data_export_csvs(%User{email: to_email}, files)
      when is_list(files) and is_binary(to_email) do
    from_name = Application.get_env(:romp_crm, :mail_from_name, "Romp CRM")
    from_address = Application.get_env(:romp_crm, :mail_from_address, "contact@example.com")

    attachments =
      Enum.map(files, fn {filename, body} ->
        body = body || <<>>
        Swoosh.Attachment.new({:data, body}, filename: filename, content_type: "text/csv")
      end)

    intro = """
    Your Romp CRM data export is attached as UTF-8 CSV files:

    - jobs.csv — jobs for businesses you created (owner only)
    - employees.csv — employees for those businesses
    - time_log.csv — job time entries and employee clock entries
    - audit_log.csv — append-only log of business-scoped changes (web and SMS) with actor user id and email

    Rows never include businesses where you are only a member (non-owner).
    """

    email_built =
      new()
      |> to(to_email)
      |> from({from_name, from_address})
      |> subject("Romp CRM — your data export")
      |> text_body(intro)
      |> attach_all_csv(attachments)

    Mailer.deliver(email_built)
  end

  defp attach_all_csv(email, attachments) do
    Enum.reduce(attachments, email, fn att, em -> attachment(em, att) end)
  end

  @doc "Notifies the user they have no owner businesses, so there is nothing to export."
  def deliver_data_export_no_owned_businesses(%User{email: email}) when is_binary(email) do
    from_name = Application.get_env(:romp_crm, :mail_from_name, "Romp CRM")
    from_address = Application.get_env(:romp_crm, :mail_from_address, "contact@example.com")

    body = """
    You asked for a Romp CRM data export, but this account does not own any businesses yet.

    Exports only include businesses you created (owner). Businesses where you were invited as a member are not included.

    Create a business in Romp CRM, then run an export again.
    """

    email =
      new()
      |> to(email)
      |> from({from_name, from_address})
      |> subject("Romp CRM — data export (nothing to export)")
      |> text_body(body)

    Mailer.deliver(email)
  end
end
