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
#     PHX_SERVER=true bin/romp_crm start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :romp_crm, RompCrmWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /home/henry/romp-crm/data/romp_crm.db
      """

  config :romp_crm, RompCrm.Repo,
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

  # WebSocket `Origin` must match the browser hostname. This app is legitimately served
  # under both hromp.com and rompcrm.com (apex + www); `PHX_HOST` alone is not enough.
  known_public_origins = [
    "https://rompcrm.com",
    "https://www.rompcrm.com",
    "https://hromp.com",
    "https://www.hromp.com"
  ]

  check_origin =
    case System.get_env("PHX_CHECK_ORIGINS") |> to_string() |> String.trim() do
      "" ->
        apex = host |> String.trim() |> String.replace_prefix("www.", "")
        derived = ["https://#{apex}", "https://www.#{apex}"]
        Enum.uniq(derived ++ known_public_origins)

      csv ->
        csv |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end

  # `/romp-crm` etc. — set at compile time in config/prod.exs (`:path_prefix`).
  path_prefix = Application.compile_env(:romp_crm, :path_prefix, "/")

  http_ip =
    if System.get_env("PHX_BIND") == "all" do
      {0, 0, 0, 0, 0, 0, 0, 0}
    else
      {127, 0, 0, 1}
    end

  config :romp_crm, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :romp_crm, RompCrmWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https", path: path_prefix],
    static_url: [path: path_prefix],
    http: [
      ip: http_ip,
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: check_origin

  mail_from_name = System.get_env("MAIL_FROM_NAME") || "Romp CRM"

  mail_from_address =
    System.get_env("MAIL_FROM_ADDRESS") ||
      raise """
      environment variable MAIL_FROM_ADDRESS is missing (From: address for magic-link and confirmation emails).
      """

  default_registration_emails =
    "151henry151@gmail.com,jvzieger@icloud.com,jzieger2@gmail.com,henry@hromp.com"

  registration_emails_raw =
    case System.get_env("ALLOWED_REGISTRATION_EMAILS") |> to_string() |> String.trim() do
      "" -> default_registration_emails
      s -> s
    end

  registration_allowlist =
    registration_emails_raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))

  # Only **true** restricts sign-ups to `registration_email_allowlist` / `ALLOWED_REGISTRATION_EMAILS`.
  # Default is open registration for self-hosted / public demos.
  enforce_registration_allowlist =
    System.get_env("ENFORCE_REGISTRATION_ALLOWLIST") == "true"

  default_twilio_from = "+18024587299,+18024582710,+18022780965"

  twilio_from_raw =
    case System.get_env("TWILIO_SMS_ALLOWED_FROM") |> to_string() |> String.trim() do
      "" -> default_twilio_from
      s -> s
    end

  twilio_allow_norm =
    twilio_from_raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&RompCrm.Twilio.Phone.normalize_us/1)
    |> Enum.reject(&(&1 == ""))

  twilio_messaging_from_raw =
    case System.get_env("TWILIO_MESSAGING_FROM") |> to_string() |> String.trim() do
      "" -> "+18022780965"
      s -> s
    end

  twilio_sms_replies_enabled =
    System.get_env("TWILIO_SMS_REPLIES_ENABLED") != "false"

  subscription_paywall_enabled =
    System.get_env("SUBSCRIPTION_PAYWALL_ENABLED") == "true"

  paypal_mode =
    case System.get_env("PAYPAL_MODE") |> to_string() |> String.downcase() do
      "live" -> "live"
      _ -> "sandbox"
    end

  paypal_skip_webhook_verify =
    System.get_env("PAYPAL_SKIP_WEBHOOK_VERIFY") == "true"

  paypal_trial_days =
    case System.get_env("PAYPAL_TRIAL_DAYS") |> to_string() |> String.trim() do
      "" ->
        14

      s ->
        case Integer.parse(s) do
          {n, _} when n >= 0 and n <= 365 ->
            n

          _ ->
            raise """
            environment variable PAYPAL_TRIAL_DAYS must be an integer from 0 to 365 (default 14).
            """
        end
    end

  {paypal_client_id, paypal_client_secret, paypal_webhook_id, paypal_plan_monthly_id,
   paypal_plan_annual_id} =
    if subscription_paywall_enabled do
      id =
        System.get_env("PAYPAL_CLIENT_ID") ||
          raise """
          environment variable PAYPAL_CLIENT_ID is missing while SUBSCRIPTION_PAYWALL_ENABLED=true.
          Use an app from developer.paypal.com (Sandbox or Live) and set PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET.
          """

      secret =
        System.get_env("PAYPAL_CLIENT_SECRET") ||
          raise """
          environment variable PAYPAL_CLIENT_SECRET is missing while SUBSCRIPTION_PAYWALL_ENABLED=true.
          """

      webhook_id =
        if paypal_skip_webhook_verify do
          System.get_env("PAYPAL_WEBHOOK_ID")
        else
          System.get_env("PAYPAL_WEBHOOK_ID") ||
            raise """
            environment variable PAYPAL_WEBHOOK_ID is missing while SUBSCRIPTION_PAYWALL_ENABLED=true and PAYPAL_SKIP_WEBHOOK_VERIFY is not true.

            Register a webhook pointing at https://YOUR_HOST/romp-crm/webhooks/paypal (path must match your PHX_PUBLIC_URL / nginx mount).
            Include billing subscription events such as ACTIVATED, CANCELLED, SUSPENDED, EXPIRED.
            """
        end

      monthly =
        System.get_env("PAYPAL_PLAN_MONTHLY_ID") ||
          raise """
          environment variable PAYPAL_PLAN_MONTHLY_ID is missing while SUBSCRIPTION_PAYWALL_ENABLED=true.
          Create subscription plans under PayPal (Products & Billing → Subscription plans) and paste the Plan ID (begins with `P-`).
          """

      annual =
        System.get_env("PAYPAL_PLAN_ANNUAL_ID") ||
          raise """
          environment variable PAYPAL_PLAN_ANNUAL_ID is missing while SUBSCRIPTION_PAYWALL_ENABLED=true.
          Create an annual plan in PayPal and paste its Plan ID (`P-...`).
          """

      {id, secret, webhook_id, monthly, annual}
    else
      {nil, nil, System.get_env("PAYPAL_WEBHOOK_ID"), System.get_env("PAYPAL_PLAN_MONTHLY_ID"),
       System.get_env("PAYPAL_PLAN_ANNUAL_ID")}
    end

  paypal_skip_verify_effective =
    not subscription_paywall_enabled or paypal_skip_webhook_verify

  config :romp_crm,
    twilio_account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
    twilio_auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
    twilio_messaging_from_number: twilio_messaging_from_raw,
    twilio_sms_replies_enabled: twilio_sms_replies_enabled,
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
    anthropic_model: System.get_env("ANTHROPIC_MODEL") || "claude-sonnet-4-20250514",
    twilio_webhook_public_url: System.get_env("TWILIO_WEBHOOK_PUBLIC_URL"),
    skip_twilio_signature_validation:
      System.get_env("SKIP_TWILIO_SIGNATURE_VALIDATION") == "true",
    mail_from_name: mail_from_name,
    mail_from_address: mail_from_address,
    registration_email_allowlist: registration_allowlist,
    enforce_registration_allowlist: enforce_registration_allowlist,
    twilio_sms_allowed_from_normalized: twilio_allow_norm,
    subscription_paywall_enabled: subscription_paywall_enabled,
    paypal_mode: paypal_mode,
    paypal_client_id: paypal_client_id,
    paypal_client_secret: paypal_client_secret,
    paypal_webhook_id: paypal_webhook_id,
    paypal_plan_monthly_id: paypal_plan_monthly_id,
    paypal_plan_annual_id: paypal_plan_annual_id,
    paypal_skip_webhook_verify: paypal_skip_verify_effective,
    paypal_brand_name: System.get_env("PAYPAL_BRAND_NAME") || mail_from_name,
    paypal_trial_days: paypal_trial_days

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

      # gen_smtp merges defaults that include `{depth, 0}` for the post-STARTTLS `ssl:connect/3`,
      # which breaks verification of normal provider chains (e.g. Sectigo / SpaceMail).
      # Upgrading a TCP socket also needs `server_name_indication` set to the SMTP hostname.
      # OS CA certs (`cacerts_get/0`) plus HTTPS-style hostname matching are required so wildcard
      # SMTP certs (e.g. `*.spacemail.com` for `mail.spacemail.com`) verify under `:verify_peer`.
      verify_host_fun = :public_key.pkix_verify_hostname_match_fun(:https)

      smtp_tls_opts = [
        {:verify, :verify_peer},
        {:cacerts, :public_key.cacerts_get()},
        {:depth, 100},
        {:server_name_indication, String.to_charlist(relay)},
        {:customize_hostname_check, [{:match_fun, verify_host_fun}]}
      ]

      # `no_mx_lookups: true` — always connect to `relay` by name. If MX lookup is
      # enabled and the host has no MX (common for submission hosts like mail.spacemail.com),
      # gen_smtp falls back to A records and connects by IP; STARTTLS then fails hostname
      # verification against a cert such as *.spacemail.com (`:tls_failed`).
      config :romp_crm, RompCrm.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: relay,
        username: smtp_username,
        password: smtp_password,
        ssl: false,
        tls: tls_mode,
        auth: if(smtp_username != "", do: :always, else: :never),
        port: smtp_port,
        no_mx_lookups: true,
        tls_options: smtp_tls_opts,
        retries: 2

      config :swoosh, :api_client, false
  end
else
  # Only apply shell PORT in dev; test uses `config/test.exs` (avoid clashing with
  # production `PORT` when running `mix test` on the same host as the release).
  if config_env() == :dev do
    config :romp_crm, RompCrmWeb.Endpoint,
      http: [port: String.to_integer(System.get_env("PORT", "4000"))]
  end
end
