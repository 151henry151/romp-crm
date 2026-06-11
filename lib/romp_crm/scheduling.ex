defmodule RompCrm.Scheduling do
  @moduledoc """
  Facade over all busy-block providers: internal jobs/bookings plus any external
  calendars (Google, Apple) the technician has connected.

  External sources degrade gracefully — if a provider errors (expired token,
  iCloud hiccup), its blocks are skipped and logged rather than failing the
  whole availability computation. The credential row records the error for the
  settings UI.
  """

  require Logger

  alias RompCrm.Scheduling.{
    AppleCalendarSource,
    AvailabilityEngine,
    CalendarCredentials,
    GoogleCalendarSource,
    InternalJobsSource
  }

  @default_sources %{
    "google" => GoogleCalendarSource,
    "apple" => AppleCalendarSource
  }

  @doc """
  Merged, sorted busy blocks for a technician within `{from_date, to_date}`:
  internal jobs + confirmed bookings for the business, plus free/busy from each
  connected external calendar. Always returns `{:ok, blocks}` — internal data is
  authoritative and external failures only narrow nothing.
  """
  @spec combined_busy_blocks(integer(), integer() | nil, {Date.t(), Date.t()}, String.t()) ::
          {:ok, [AvailabilityEngine.block()]}
  def combined_busy_blocks(business_id, technician_user_id, {_from, _to} = range, timezone) do
    {:ok, internal} =
      InternalJobsSource.fetch_busy_blocks(%{business_id: business_id}, range, timezone)

    external =
      technician_user_id
      |> connected_credentials()
      |> Enum.flat_map(fn cred ->
        case source_module(cred.source) do
          nil ->
            []

          mod ->
            case mod.fetch_busy_blocks(cred, range, timezone) do
              {:ok, blocks} ->
                blocks

              {:error, reason} ->
                Logger.warning(
                  "external calendar #{cred.source} for user #{cred.user_id} failed: #{inspect(reason)}"
                )

                []
            end
        end
      end)

    {:ok, AvailabilityEngine.merge_busy_blocks(internal ++ external)}
  end

  defp connected_credentials(nil), do: []

  defp connected_credentials(user_id) do
    user_id
    |> CalendarCredentials.list_for_user()
    |> Enum.reject(&(&1.status == "disconnected"))
  end

  defp source_module(source) do
    overrides = Application.get_env(:romp_crm, :calendar_source_overrides) || %{}
    Map.get(overrides, source) || Map.get(@default_sources, source)
  end
end
