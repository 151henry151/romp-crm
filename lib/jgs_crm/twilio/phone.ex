defmodule JgsCrm.Twilio.Phone do
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
end
