defmodule RompCrm.Accounts.UserNotifier do
  import Swoosh.Email

  alias RompCrm.Mailer
  alias RompCrm.Accounts.User
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

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    text = """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("Confirm your new email")),
        EmailHtml.p(EmailHtml.escape("Hi #{user.email},")),
        EmailHtml.p(EmailHtml.escape("Use the button below to confirm this change.")),
        EmailHtml.cta_button(url, "Confirm email"),
        EmailHtml.url_fallback(url),
        EmailHtml.muted_p(
          EmailHtml.escape("If you didn't request this change, you can ignore this email.")
        )
      ]
      |> Enum.join()

    deliver(user.email, "Update email instructions", text, inner)
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
    text = """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("Log in to Romp CRM")),
        EmailHtml.p(EmailHtml.escape("Hi #{user.email},")),
        EmailHtml.p(
          EmailHtml.escape("Tap the button below to open Romp CRM and sign in. The link expires after a short time.")
        ),
        EmailHtml.cta_button(url, "Open Romp CRM"),
        EmailHtml.url_fallback(url),
        EmailHtml.muted_p(
          EmailHtml.escape("If you didn't request this email, you can ignore it.")
        )
      ]
      |> Enum.join()

    deliver(user.email, "Log in instructions", text, inner)
  end

  defp deliver_confirmation_instructions(user, url) do
    text = """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("Confirm your account")),
        EmailHtml.p(EmailHtml.escape("Hi #{user.email},")),
        EmailHtml.p(
          EmailHtml.escape(
            "Welcome to Romp CRM. Tap the button below to confirm your email and finish signing up."
          )
        ),
        EmailHtml.cta_button(url, "Confirm and continue"),
        EmailHtml.url_fallback(url),
        EmailHtml.muted_p(
          EmailHtml.escape("If you didn't create an account with us, you can ignore this email.")
        )
      ]
      |> Enum.join()

    deliver(user.email, "Confirmation instructions", text, inner)
  end

  @doc """
  Sends export files for **owner** businesses only. **`files`** is **`{filename, body}`** (UTF-8 CSV).

  When **more than two** files are included, attaches a **single ZIP** instead of separate CSV attachments.
  """
  def deliver_data_export_csvs(%User{email: to_email}, files)
      when is_list(files) and is_binary(to_email) do
    use_zip? = length(files) > 2

    with {:ok, attachments} <- build_export_attachments(files, use_zip?) do
      intro = data_export_email_intro(files, use_zip?)
      inner = data_export_email_html(files, use_zip?)

      email_built =
        base_email(to_email)
        |> subject("Romp CRM — your data export")
        |> text_body(intro)
        |> html_body(EmailHtml.layout(inner))
        |> attach_all_csv(attachments)

      Mailer.deliver(email_built)
    end
  end

  defp data_export_email_html(files, use_zip?) do
    bullets =
      files
      |> Enum.map(fn {fname, _} ->
        EmailHtml.escape("#{fname} — #{data_export_file_blurb(fname)}")
      end)

    scope =
      EmailHtml.escape(
        "Owner workspaces only (from Settings)—not businesses where you're only a member."
      )

    intro_p =
      if use_zip? do
        EmailHtml.p(
          EmailHtml.escape("Your export is attached as one ZIP file (UTF-8 CSVs inside).")
        )
      else
        EmailHtml.p(EmailHtml.escape("Your export is attached as UTF-8 CSV file(s)."))
      end

    [
      EmailHtml.h1(EmailHtml.escape("Your data export")),
      intro_p,
      EmailHtml.bullet_list(bullets),
      EmailHtml.muted_p(scope)
    ]
    |> Enum.join()
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

  defp data_export_file_blurb("clients.csv"), do: "clients (persistent contact records)"

  defp data_export_file_blurb("employees.csv"), do: "employees"

  defp data_export_file_blurb("time_log.csv"), do: "job + employee time"

  defp data_export_file_blurb("audit_log.csv"),
    do: "business-scoped audit (summary, SMS text, change details, full metadata JSON)"

  defp data_export_file_blurb(fname), do: fname

  defp attach_all_csv(email, attachments) do
    Enum.reduce(attachments, email, fn att, em -> attachment(em, att) end)
  end

  @doc """
  Notifies **`to_email`** they received a gifted subscription; **`redeem_url`** opens the redemption page.
  """
  def deliver_gift_subscription_email(to_email, redeem_url, duration_days, admin_message)
      when is_binary(to_email) and is_binary(redeem_url) and is_integer(duration_days) do
    period = "#{duration_days} day" <> if(duration_days == 1, do: "", else: "s")

    {note_text, note_html} = gift_admin_note(admin_message)

    text = """

    ==============================

    You've been gifted a #{period} Romp CRM subscription (no card required).
    #{note_text}
    Open this link to activate your gift:
    #{redeem_url}

    If you already have a Romp CRM account with this email, the link takes you to sign in and applies the gift after you log in. If you are new, the same link creates your account and signs you in.

    If you did not expect this email, you can ignore it.

    ==============================
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("You've been gifted Romp CRM")),
        EmailHtml.p(
          EmailHtml.escape("You've been gifted a #{period} subscription—no card required.")
        ),
        note_html,
        EmailHtml.cta_button(redeem_url, "Activate your gift"),
        EmailHtml.url_fallback(redeem_url),
        EmailHtml.p(
          EmailHtml.escape(
            "If you already have a Romp CRM account with this email, the link takes you to sign in and applies the gift after you log in. If you're new, the same link creates your account and signs you in."
          )
        ),
        EmailHtml.muted_p(EmailHtml.escape("If you did not expect this email, you can ignore it."))
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join()

    deliver(to_email, "You've been gifted Romp CRM (#{period})", text, inner)
  end

  defp gift_admin_note(admin_message) do
    case admin_message do
      s when is_binary(s) ->
        t = String.trim(s)

        if t != "" do
          txt = "\n\nMessage from the team:\n#{t}\n"

          html =
            EmailHtml.callout(
              "<p style=\"margin:0;font-family:'Inter','Segoe UI',Roboto,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:14px;line-height:1.55;color:#374151;\"><strong style=\"color:#111827;\">" <>
                EmailHtml.escape("Message from the team") <>
                "</strong><br />" <>
                EmailHtml.multiline_html(t) <>
                "</p>"
            )

          {txt, html}
        else
          {"", ""}
        end

      _ ->
        {"", ""}
    end
  end

  @doc "Notifies the user they have no owner businesses, so there is nothing to export."
  def deliver_data_export_no_owned_businesses(%User{email: email}) when is_binary(email) do
    body = """
    No export yet—this account doesn't own any workspaces.

    Create a business, then export again.
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("Nothing to export yet")),
        EmailHtml.p(
          EmailHtml.escape("This account doesn't own any workspaces, so there are no CSV files to attach.")
        ),
        EmailHtml.p(EmailHtml.escape("Create a business in Romp CRM, then run the export again from Settings."))
      ]
      |> Enum.join()

    email =
      base_email(email)
      |> subject("Romp CRM — data export (nothing to export)")
      |> text_body(body)
      |> html_body(EmailHtml.layout(inner))

    Mailer.deliver(email)
  end

  @doc """
  Notifies an operator address that a new Romp CRM account was created.

  **`via`** is `:standard`, `:invitation`, or `:gift`.
  """
  def deliver_signup_admin_notification(to_email, %User{} = user, via)
      when is_binary(to_email) and via in [:standard, :invitation, :gift] do
    {via_label, via_detail} = signup_via_copy(via, user)
    status = user.subscription_status || "unknown"

    text = """
    A new Romp CRM account was created.

    Email: #{user.email}
    User ID: #{user.id}
    Sign-up type: #{via_label}
    Subscription status: #{status}
    #{via_detail}
    """

    inner =
      [
        EmailHtml.h1(EmailHtml.escape("New Romp CRM sign-up")),
        EmailHtml.p(EmailHtml.escape("A new account was created on Romp CRM.")),
        EmailHtml.bullet_list([
          EmailHtml.escape("Email: #{user.email}"),
          EmailHtml.escape("User ID: #{user.id}"),
          EmailHtml.escape("Sign-up type: #{via_label}"),
          EmailHtml.escape("Subscription status: #{status}")
        ]),
        signup_via_html(via_detail)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join()

    deliver(to_email, "Romp CRM — new account: #{user.email}", String.trim(text), inner)
  end

  defp signup_via_copy(:standard, _user) do
    {"Standard registration", ""}
  end

  defp signup_via_copy(:invitation, _user) do
    {"Business invitation", "The user registered from a team invitation link."}
  end

  defp signup_via_copy(:gift, _user) do
    {"Gift redemption", "The user was created when redeeming a gifted subscription."}
  end

  defp signup_via_html(""), do: ""

  defp signup_via_html(detail) when is_binary(detail) do
    EmailHtml.muted_p(EmailHtml.escape(detail))
  end
end
