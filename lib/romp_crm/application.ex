defmodule RompCrm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        RompCrmWeb.Telemetry,
        RompCrm.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:romp_crm, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:romp_crm, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: RompCrm.PubSub},
        {Finch, name: RompCrm.Finch},
        RompCrmWeb.Endpoint
      ] ++
        chromic_pdf_child() ++
        data_export_scheduler_child() ++
        reminder_scheduler_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RompCrm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RompCrmWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp chromic_pdf_child do
    if Application.get_env(:romp_crm, :chromic_pdf_enabled, true) do
      chrome =
        Application.get_env(:romp_crm, :chromic_pdf_chrome_path, "/usr/bin/chromium")

      [
        {ChromicPDF,
         [
           chrome_executable: chrome,
           # Job PDFs with many photos need more than the default 5s session timeout.
           session_pool: [
             timeout: 60_000,
             checkout_timeout: 30_000,
             init_timeout: 30_000
           ]
         ]}
      ]
    else
      []
    end
  end

  defp data_export_scheduler_child do
    if Application.get_env(:romp_crm, :data_export_scheduler_enabled, true) do
      [{RompCrm.DataExportScheduler, []}]
    else
      []
    end
  end

  defp reminder_scheduler_child do
    if Application.get_env(:romp_crm, :reminder_scheduler_enabled, true) do
      [{RompCrm.ReminderScheduler, []}]
    else
      []
    end
  end
end
