defmodule RompCrm.ReminderScheduler do
  @moduledoc """
  Periodically runs **`RompCrm.Reminders.run_scheduled_deliveries/1`**.

  Disabled in **`test`** via **`config :romp_crm, :reminder_scheduler_enabled, false`**.
  """

  use GenServer

  @interval_ms 120_000

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
    if Application.get_env(:romp_crm, :reminder_scheduler_enabled, true) do
      _ = RompCrm.Reminders.run_scheduled_deliveries()
    end

    schedule_tick()
    {:noreply, state}
  end
end
