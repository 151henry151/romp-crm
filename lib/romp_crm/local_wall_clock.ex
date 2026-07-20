defmodule RompCrm.LocalWallClock do
  @moduledoc """
  Naive local wall-clock helpers for fields documented as business-local
  (employee punches, job hours defaults, SMS "now" times).
  """

  @default_tz "America/New_York"

  @doc "Current wall-clock time in `tz` as a truncated naive datetime."
  def now(tz \\ @default_tz) when is_binary(tz) do
    case DateTime.now(tz) do
      {:ok, dt} ->
        dt |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

      {:error, _} ->
        DateTime.now!(@default_tz) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    end
  end

  @doc "Current calendar date in `tz`."
  def today(tz \\ @default_tz) when is_binary(tz) do
    now(tz) |> NaiveDateTime.to_date()
  end

  @doc "Default IANA zone used when a user preference is missing."
  def default_timezone, do: @default_tz
end
