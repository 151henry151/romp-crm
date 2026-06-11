defmodule RompCrm.Scheduling.Prefs do
  @moduledoc """
  Technician scheduling preferences decoded from `users.scheduling_prefs_json`:
  timezone, working hours, work days (ISO day numbers, Monday = 1), and the
  travel/buffer minutes inserted between jobs.

  Invalid or missing values fall back to defaults rather than erroring, mirroring
  `RompCrm.Reminders.decode_prefs_json/1`.
  """

  @derive Jason.Encoder
  defstruct timezone: "America/New_York",
            workday_start: ~T[08:00:00],
            workday_end: ~T[17:00:00],
            work_days: [1, 2, 3, 4, 5],
            buffer_minutes: 30

  @type t :: %__MODULE__{
          timezone: String.t(),
          workday_start: Time.t(),
          workday_end: Time.t(),
          work_days: [1..7],
          buffer_minutes: non_neg_integer()
        }

  def default, do: %__MODULE__{}

  @doc "Decodes the prefs JSON string; nil/blank/invalid input yields defaults."
  def decode(nil), do: default()
  def decode(""), do: default()

  def decode(json) when is_binary(json) do
    case Jason.decode(String.trim(json)) do
      {:ok, %{} = raw} ->
        %__MODULE__{
          timezone: normalize_timezone(Map.get(raw, "timezone")),
          workday_start: parse_time(Map.get(raw, "workday_start"), ~T[08:00:00]),
          workday_end: parse_time(Map.get(raw, "workday_end"), ~T[17:00:00]),
          work_days: normalize_work_days(Map.get(raw, "work_days")),
          buffer_minutes: normalize_buffer(Map.get(raw, "buffer_minutes"))
        }

      _ ->
        default()
    end
  end

  @doc "Encodes prefs back to the JSON string stored on the user row."
  def encode(%__MODULE__{} = prefs) do
    Jason.encode!(%{
      "timezone" => prefs.timezone,
      "workday_start" => Time.to_iso8601(prefs.workday_start) |> String.slice(0, 5),
      "workday_end" => Time.to_iso8601(prefs.workday_end) |> String.slice(0, 5),
      "work_days" => prefs.work_days,
      "buffer_minutes" => prefs.buffer_minutes
    })
  end

  defp normalize_timezone(tz) do
    tz = tz |> to_string() |> String.trim()

    case DateTime.now(tz) do
      {:ok, _} -> tz
      _ -> "America/New_York"
    end
  end

  defp parse_time(raw, fallback) do
    raw = raw |> to_string() |> String.trim()

    candidate = if Regex.match?(~r/^\d{2}:\d{2}$/, raw), do: raw <> ":00", else: raw

    case Time.from_iso8601(candidate) do
      {:ok, t} -> t
      _ -> fallback
    end
  end

  defp normalize_work_days(raw) do
    days =
      raw
      |> List.wrap()
      |> Enum.filter(&(is_integer(&1) and &1 in 1..7))
      |> Enum.uniq()
      |> Enum.sort()

    if days == [], do: [1, 2, 3, 4, 5], else: days
  end

  defp normalize_buffer(raw) when is_integer(raw) and raw >= 0 and raw <= 240, do: raw
  defp normalize_buffer(_), do: 0
end
