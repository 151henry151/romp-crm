defmodule RompCrmWeb.UserSessionHTML do
  use RompCrmWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:romp_crm, RompCrm.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
