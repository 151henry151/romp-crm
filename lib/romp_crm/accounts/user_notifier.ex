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
  Sends export files for **owner** businesses only. **`files`** is **`{filename, body}`** (UTF-8 CSV).

  When **more than two** files are included, attaches a **single ZIP** instead of separate CSV attachments.
  """
  def deliver_data_export_csvs(%User{email: to_email}, files)
      when is_list(files) and is_binary(to_email) do
    from_name = Application.get_env(:romp_crm, :mail_from_name, "Romp CRM")
    from_address = Application.get_env(:romp_crm, :mail_from_address, "contact@example.com")

    use_zip? = length(files) > 2

    with {:ok, attachments} <- build_export_attachments(files, use_zip?) do
      intro = data_export_email_intro(files, use_zip?)

      email_built =
        new()
        |> to(to_email)
        |> from({from_name, from_address})
        |> subject("Romp CRM — your data export")
        |> text_body(intro)
        |> attach_all_csv(attachments)

      Mailer.deliver(email_built)
    end
  end

  defp build_export_attachments(files, true) do
    case RompCrm.DataExport.build_download_payload(files) do
      {:ok, {:zip, body}} ->
        {:ok,
         [
           Swoosh.Attachment.new({:data, body},
             filename: "romp-crm-export.zip",
             content_type: "application/zip"
           )
         ]}

      {:error, reason} ->
        {:error, {:zip_failed, reason}}
    end
  end

  defp build_export_attachments(files, false) do
    atts =
      Enum.map(files, fn {filename, body} ->
        body = body || <<>>
        Swoosh.Attachment.new({:data, body}, filename: filename, content_type: "text/csv")
      end)

    {:ok, atts}
  end

  defp data_export_email_intro(files, use_zip?) when use_zip? do
    bullets =
      files
      |> Enum.map(fn {fname, _} -> "  - #{fname} — #{data_export_file_blurb(fname)}" end)
      |> Enum.join("\n")

    """
    Export attached as one ZIP (UTF-8 CSVs inside):

    #{bullets}

    Owner workspaces only (from Settings)—not businesses where you're only a member.
    """
    |> String.trim()
  end

  defp data_export_email_intro(files, _use_zip?) do
    bullets =
      files
      |> Enum.map(fn {fname, _} -> "  - #{fname} — #{data_export_file_blurb(fname)}" end)
      |> Enum.join("\n")

    """
    Export attached as UTF-8 CSV(s):

    #{bullets}

    Owner workspaces only (from Settings)—not businesses where you're only a member.
    """
    |> String.trim()
  end

  defp data_export_file_blurb("jobs.csv"), do: "jobs (owner businesses)"

  defp data_export_file_blurb("employees.csv"), do: "employees"

  defp data_export_file_blurb("time_log.csv"), do: "job + employee time"

  defp data_export_file_blurb("audit_log.csv"), do: "business-scoped changes (actor id + email)"

  defp data_export_file_blurb(fname), do: fname

  defp attach_all_csv(email, attachments) do
    Enum.reduce(attachments, email, fn att, em -> attachment(em, att) end)
  end

  @doc "Notifies the user they have no owner businesses, so there is nothing to export."
  def deliver_data_export_no_owned_businesses(%User{email: email}) when is_binary(email) do
    from_name = Application.get_env(:romp_crm, :mail_from_name, "Romp CRM")
    from_address = Application.get_env(:romp_crm, :mail_from_address, "contact@example.com")

    body = """
    No export yet—this account doesn't own any workspaces.

    Create a business, then export again.
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
