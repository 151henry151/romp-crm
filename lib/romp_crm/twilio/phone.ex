defmodule RompCrm.Twilio.Phone do
  @moduledoc false

  @doc """
  Normalize North-American caller IDs for equality checks.

  Twilio commonly sends `From` as `+18024587299`; users may configure allowlists with
  spaces, dashes, or parentheses — all map to the same 11-digit string starting with `1`.
  """
  def normalize_us(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/\D/, "")

    cond do
      digits == "" ->
        ""

      byte_size(digits) == 10 ->
        "1" <> digits

      byte_size(digits) == 11 and String.starts_with?(digits, "1") ->
        digits

      true ->
        digits
    end
  end

  def normalize_us(_), do: ""

  @doc """
  Pretty-print for UI: `+18022780965` → `(802) 278-0965`.
  Falls back to trimmed input when normalization does not yield NANP 10 digits under leading `1`.
  """
  def format_us_display(raw) when is_binary(raw) do
    n = normalize_us(raw)

    rest =
      cond do
        String.length(n) == 11 and String.starts_with?(n, "1") ->
          String.slice(n, 1..-1//1)

        String.length(n) == 10 ->
          n

        true ->
          nil
      end

    case rest do
      <<a::binary-size(3), b::binary-size(3), c::binary-size(4)>> ->
        "(#{a}) #{b}-#{c}"

      _ ->
        raw |> String.trim()
    end
  end

  def format_us_display(_), do: ""

  @doc """
  `sms:` URI for `<a href>` — uses normalized NANP when possible.
  """
  def sms_uri(raw) when is_binary(raw) do
    n = normalize_us(raw)

    cond do
      String.length(n) == 11 and String.starts_with?(n, "1") ->
        "sms:+#{n}"

      String.length(n) == 10 ->
        "sms:+1#{n}"

      true ->
        t = String.trim(raw)
        if String.starts_with?(t, "+"), do: "sms:#{t}", else: "sms:+#{t}"
    end
  end

  def sms_uri(_), do: "sms:"

  @doc """
  Converts internal **`phone_normalized`** (NANP digits, typically `1` + 10 digits) to **E.164**
  for Twilio (`+1…`). Returns **`nil`** when normalization does not yield a valid NANP mobile/line.
  """
  def to_e164(nil), do: nil

  def to_e164(norm) when is_binary(norm) and norm != "" do
    if String.starts_with?(norm, "1") and byte_size(norm) == 11 do
      "+" <> norm
    else
      case normalize_us(norm) do
        "" ->
          nil

        n ->
          if String.starts_with?(n, "1") and byte_size(n) == 11, do: "+" <> n, else: nil
      end
    end
  end

  def to_e164(_), do: nil
end
