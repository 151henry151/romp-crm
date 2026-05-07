defmodule RompCrm.Repo do
  use Ecto.Repo,
    otp_app: :romp_crm,
    adapter: Ecto.Adapters.SQLite3
end
