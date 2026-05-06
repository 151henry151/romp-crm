defmodule JgsCrm.Release do
  @moduledoc """
  Migration helpers for production releases (`mix` not available).

      bin/jgs_crm eval "JgsCrm.Release.migrate"
  """
  @app :jgs_crm

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(@app)
  end
end
