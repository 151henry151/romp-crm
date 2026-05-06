defmodule JgsCrmWeb.UserSessionHTML do
  use JgsCrmWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:jgs_crm, JgsCrm.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
