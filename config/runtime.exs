import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/jgs_crm start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :jgs_crm, JgsCrmWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /home/henry/jgs-crm/data/jgs_crm.db
      """

  config :jgs_crm, JgsCrm.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # `/jgs-crm` etc. — set at compile time in config/prod.exs (`:path_prefix`).
  path_prefix = Application.compile_env(:jgs_crm, :path_prefix, "/")

  http_ip =
    if System.get_env("PHX_BIND") == "all" do
      {0, 0, 0, 0, 0, 0, 0, 0}
    else
      {127, 0, 0, 1}
    end

  config :jgs_crm, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :jgs_crm, JgsCrmWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https", path: path_prefix],
    static_url: [path: path_prefix],
    http: [
      ip: http_ip,
      port: port
    ],
    secret_key_base: secret_key_base

  mail_from_name = System.get_env("MAIL_FROM_NAME") || "JGS CRM"

  mail_from_address =
    System.get_env("MAIL_FROM_ADDRESS") ||
      raise """
      environment variable MAIL_FROM_ADDRESS is missing (From: address for magic-link and confirmation emails).
      """

  config :jgs_crm,
    twilio_auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
    anthropic_model: System.get_env("ANTHROPIC_MODEL") || "claude-sonnet-4-20250514",
    twilio_webhook_public_url: System.get_env("TWILIO_WEBHOOK_PUBLIC_URL"),
    skip_twilio_signature_validation: System.get_env("SKIP_TWILIO_SIGNATURE_VALIDATION") == "true",
    mail_from_name: mail_from_name,
    mail_from_address: mail_from_address

  case System.get_env("SMTP_HOST") |> to_string() |> String.trim() do
    "" ->
      raise """
      environment variable SMTP_HOST is missing.
      Set SMTP_HOST (e.g. smtp.gmail.com), SMTP_PORT (often 587), SMTP_USERNAME, SMTP_PASSWORD,
      and optionally SMTP_TLS (always | if_available | never).
      """

    relay ->
      smtp_port = String.to_integer(System.get_env("SMTP_PORT") || "587")

      smtp_username = System.get_env("SMTP_USERNAME") || ""

      smtp_password = System.get_env("SMTP_PASSWORD") || ""

      tls_mode =
        case String.downcase(System.get_env("SMTP_TLS") || "always") do
          "never" -> :never
          "if_available" -> :if_available
          _ -> :always
        end

      config :jgs_crm, JgsCrm.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: relay,
        username: smtp_username,
        password: smtp_password,
        ssl: false,
        tls: tls_mode,
        auth: if(smtp_username != "", do: :always, else: :never),
        port: smtp_port,
        retries: 2

      config :swoosh, :api_client, false
  end
else
  # Only apply shell PORT in dev; test uses `config/test.exs` (avoid clashing with
  # production `PORT` when running `mix test` on the same host as the release).
  if config_env() == :dev do
    config :jgs_crm, JgsCrmWeb.Endpoint,
      http: [port: String.to_integer(System.get_env("PORT", "4000"))]
  end
end
