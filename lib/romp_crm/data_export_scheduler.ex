defmodule RompCrm.DataExportScheduler do
  @moduledoc """
  Periodically runs **`RompCrm.DataExport.run_due_exports/0`** for users with an active schedule.

  Disabled in **`test`** via **`config :romp_crm, :data_export_scheduler_enabled, false`**.
  """

  use GenServer

  @interval_ms 300_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @interval_ms)
  end

  @impl true
  def handle_info(:tick, state) do
    if Application.get_env(:romp_crm, :data_export_scheduler_enabled, true) do
      _ = RompCrm.DataExport.run_due_exports()
    end

    schedule_tick()
    {:noreply, state}
  end
end
