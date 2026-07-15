import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :romp_crm, RompCrm.Repo,
  database: Path.expand("../romp_crm_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  busy_timeout: 15_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :romp_crm, RompCrmWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  secret_key_base: "M37PfkfxFRHgxCXjy+qjwtpGeDHTwDqq0GsWeXa4Wx6I1TBPxZhUfcFjotalOJ9Z",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :romp_crm,
  skip_twilio_signature_validation: true,
  admin_emails: ["admin.romp.test@example.com"],
  sms_job_extractor_adapter: RompCrm.Ai.SmsJobExtractor.DeterministicStub,
  sms_time_extractor_adapter: RompCrm.Ai.SmsTimeExtractor.DeterministicStub,
  sms_employee_time_extractor_adapter: RompCrm.Ai.SmsEmployeeTimeExtractor.DeterministicStub,
  sms_unified_inbound_adapter: RompCrm.Ai.SmsUnifiedInboundExtractor.DeterministicStub,
  customer_booking_adapter: RompCrm.Ai.CustomerBookingExtractor.DeterministicStub,
  scheduling_playbook_adapter: RompCrm.Ai.SchedulingPlaybookExtractor.DeterministicStub,
  booking_escalation_adapter: RompCrm.Ai.BookingEscalationExtractor.DeterministicStub,
  enforce_registration_allowlist: false,
  subscription_paywall_enabled: false,
  paypal_skip_webhook_verify: true,
  paypal_trial_days: 14,
  twilio_sms_allowed_from_normalized: ["15555550123"],
  twilio_account_sid: nil,
  twilio_messaging_from_number: "+15551234567",
  twilio_sms_replies_enabled: false,
  twilio_voice_webhook_public_url: "https://example.test/romp-crm/webhooks/twilio/voice",
  twilio_voice_forward_e164: "+18024587299",
  data_export_scheduler_enabled: false,
  reminder_scheduler_enabled: false,
  customer_scheduling_sms_enabled: true,
  signup_notify_emails: []

config :romp_crm, RompCrm.Mailer, adapter: Swoosh.Adapters.Test
