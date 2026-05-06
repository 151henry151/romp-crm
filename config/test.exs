import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :jgs_crm, JgsCrm.Repo,
  database: Path.expand("../jgs_crm_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :jgs_crm, JgsCrmWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
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

config :jgs_crm,
  skip_twilio_signature_validation: true,
  sms_job_extractor_adapter: JgsCrm.Ai.SmsJobExtractor.DeterministicStub,
  enforce_registration_allowlist: false,
  twilio_sms_allowed_from_normalized: ["15555550123"]
