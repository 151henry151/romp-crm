defmodule RompCrm.Scheduling.Prefs do
  @moduledoc """
  Technician scheduling preferences decoded from `users.scheduling_prefs_json`:
  timezone, working hours, work days (ISO day numbers, Monday = 1), buffer between
  jobs, customer outreach style, minimum lead time, and scheduling bias.

  Invalid or missing values fall back to defaults rather than erroring, mirroring
  `RompCrm.Reminders.decode_prefs_json/1`.
  """

  alias RompCrm.Accounts.User
  alias RompCrm.Scheduling.TimezoneInference

  @outreach_styles ~w(ask offer offer_then_ask)
  @scheduling_biases ~w(asap spread)

  @derive Jason.Encoder
  defstruct timezone: "America/New_York",
            workday_start: ~T[08:00:00],
            workday_end: ~T[17:00:00],
            work_days: [1, 2, 3, 4, 5],
            buffer_minutes: 30,
            customer_outreach_style: "offer_then_ask",
            min_lead_days: 0,
            scheduling_bias: nil

  @type t :: %__MODULE__{
          timezone: String.t(),
          workday_start: Time.t(),
          workday_end: Time.t(),
          work_days: [1..7],
          buffer_minutes: non_neg_integer(),
          customer_outreach_style: String.t(),
          min_lead_days: non_neg_integer(),
          scheduling_bias: String.t() | nil
        }

  def default, do: %__MODULE__{}
  def outreach_styles, do: @outreach_styles

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
          buffer_minutes: normalize_buffer(Map.get(raw, "buffer_minutes")),
          customer_outreach_style:
            normalize_outreach_style(Map.get(raw, "customer_outreach_style")),
          min_lead_days: normalize_min_lead_days(Map.get(raw, "min_lead_days")),
          scheduling_bias: normalize_scheduling_bias(Map.get(raw, "scheduling_bias"))
        }

      _ ->
        default()
    end
  end

  @doc "Encodes prefs back to the JSON string stored on the user row."
  def encode(%__MODULE__{} = prefs) do
    base = %{
      "timezone" => prefs.timezone,
      "workday_start" => Time.to_iso8601(prefs.workday_start) |> String.slice(0, 5),
      "workday_end" => Time.to_iso8601(prefs.workday_end) |> String.slice(0, 5),
      "work_days" => prefs.work_days,
      "buffer_minutes" => prefs.buffer_minutes,
      "customer_outreach_style" => prefs.customer_outreach_style,
      "min_lead_days" => prefs.min_lead_days
    }

    Jason.encode!(
      if prefs.scheduling_bias do
        Map.put(base, "scheduling_bias", prefs.scheduling_bias)
      else
        base
      end
    )
  end

  @doc """
  Ensures the user has persisted scheduling prefs with an inferred timezone when
  none are stored yet. Does not overwrite an existing JSON blob.
  """
  def ensure_initialized(%User{} = user, opts \\ []) do
    if is_binary(user.scheduling_prefs_json) and String.trim(user.scheduling_prefs_json) != "" do
      {:ok, user}
    else
      tz =
        Keyword.get_lazy(opts, :timezone, fn ->
          user.phone_normalized
          |> Kernel.||(user.phone)
          |> TimezoneInference.from_phone()
        end)

      prefs = %__MODULE__{timezone: tz}
      RompCrm.Accounts.update_user_scheduling_prefs(user, encode(prefs))
    end
  end

  @doc "Merges a map of string-keyed updates into existing prefs and returns encoded JSON."
  def merge_encoded(nil, updates) when is_map(updates) do
    decode(nil) |> merge_struct(updates) |> encode()
  end

  def merge_encoded(json, updates) when is_binary(json) and is_map(updates) do
    json |> decode() |> merge_struct(updates) |> encode()
  end

  defp merge_struct(%__MODULE__{} = prefs, updates) when is_map(updates) do
    %{
      timezone: Map.get(updates, "timezone") || Map.get(updates, :timezone),
      workday_start: Map.get(updates, "workday_start") || Map.get(updates, :workday_start),
      workday_end: Map.get(updates, "workday_end") || Map.get(updates, :workday_end),
      work_days: Map.get(updates, "work_days") || Map.get(updates, :work_days),
      buffer_minutes: Map.get(updates, "buffer_minutes") || Map.get(updates, :buffer_minutes),
      customer_outreach_style:
        Map.get(updates, "customer_outreach_style") || Map.get(updates, :customer_outreach_style),
      min_lead_days: Map.get(updates, "min_lead_days") || Map.get(updates, :min_lead_days),
      scheduling_bias: Map.get(updates, "scheduling_bias") || Map.get(updates, :scheduling_bias)
    }
    |> Enum.reduce(prefs, fn
      {_, nil}, acc -> acc
      {:timezone, v}, acc -> %{acc | timezone: normalize_timezone(v)}
      {:workday_start, v}, acc -> %{acc | workday_start: parse_time(v, acc.workday_start)}
      {:workday_end, v}, acc -> %{acc | workday_end: parse_time(v, acc.workday_end)}
      {:work_days, v}, acc -> %{acc | work_days: normalize_work_days(v)}
      {:buffer_minutes, v}, acc -> %{acc | buffer_minutes: normalize_buffer(v)}
      {:customer_outreach_style, v}, acc -> %{acc | customer_outreach_style: normalize_outreach_style(v)}
      {:min_lead_days, v}, acc -> %{acc | min_lead_days: normalize_min_lead_days(v)}
      {:scheduling_bias, v}, acc -> %{acc | scheduling_bias: normalize_scheduling_bias(v)}
    end)
  end

  defp normalize_timezone(tz) do
    tz = tz |> to_string() |> String.trim()

    case DateTime.now(tz) do
      {:ok, _} -> tz
      _ -> "America/New_York"
    end
  end

  defp parse_time(%Time{} = t), do: t

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

  defp normalize_buffer(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, _} -> normalize_buffer(n)
      :error -> 30
    end
  end

  defp normalize_buffer(_), do: 0

  defp normalize_outreach_style(style) when style in @outreach_styles, do: style

  defp normalize_outreach_style(style) when is_binary(style) do
    s = String.downcase(String.trim(style))

    cond do
      s in ["a", "ask", "ask_first", "ask what works"] -> "ask"
      s in ["b", "offer", "offer_first", "offer slots"] -> "offer"
      s in ["c", "offer_then_ask", "both", "hybrid"] -> "offer_then_ask"
      true -> "offer_then_ask"
    end
  end

  defp normalize_outreach_style(_), do: "offer_then_ask"

  defp normalize_min_lead_days(n) when is_integer(n) and n >= 0 and n <= 90, do: n

  defp normalize_min_lead_days(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> normalize_min_lead_days(i)
      :error -> 0
    end
  end

  defp normalize_min_lead_days(_), do: 0

  defp normalize_scheduling_bias(bias) when bias in @scheduling_biases, do: bias

  defp normalize_scheduling_bias(bias) when is_binary(bias) do
    case String.downcase(String.trim(bias)) do
      "asap" -> "asap"
      "soonest" -> "asap"
      "spread" -> "spread"
      _ -> nil
    end
  end

  defp normalize_scheduling_bias(_), do: nil
end
