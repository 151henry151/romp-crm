defmodule JgsCrm.Repo do
  use Ecto.Repo,
    otp_app: :jgs_crm,
    adapter: Ecto.Adapters.SQLite3
end
