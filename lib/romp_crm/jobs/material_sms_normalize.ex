defmodule RompCrm.Jobs.MaterialSmsNormalize do
  @moduledoc false

  @word_qty %{
    "one" => 1.0,
    "two" => 2.0,
    "three" => 3.0,
    "four" => 4.0,
    "five" => 5.0,
    "six" => 6.0,
    "seven" => 7.0,
    "eight" => 8.0,
    "nine" => 9.0,
    "ten" => 10.0,
    "eleven" => 11.0,
    "twelve" => 12.0
  }

  @doc """
  Derives persisted **`quantity`** and **`description`** for a material line from SMS/AI JSON.

  When the model sends **`quantity` strictly greater than 1**, that value is trusted and the
  description string is left unchanged.

  When **`quantity` is missing, `null`, or `1`**, peels a leading count from the description when
  the text clearly starts with a spoken number (**one** … **twelve**) or a leading integer **≥ 2**
  followed by the rest of the line (e.g. **2 1 1/4" P traps** → qty **2**, name **1 1/4" P traps**).
  Leading integer **1** is not peeled (avoids splitting sizes like **1 1/4 inch**).
  """
  @spec quantity_and_description(String.t(), number() | String.t() | nil) :: {float(), String.t()}
  def quantity_and_description(description, explicit_quantity) when is_binary(description) do
    desc = String.trim(description)
    explicit_f = to_float_quantity(explicit_quantity)

    if explicit_f != nil and explicit_f > 1.0 do
      {explicit_f, desc}
    else
      infer_leading_count(desc)
    end
  end

  defp to_float_quantity(nil), do: nil
  defp to_float_quantity(n) when is_float(n), do: n
  defp to_float_quantity(n) when is_integer(n), do: n * 1.0

  defp to_float_quantity(n) when is_binary(n) do
    case Float.parse(String.trim(n)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp to_float_quantity(_), do: nil

  defp infer_leading_count(desc) do
    cond do
      m =
          Regex.run(
            ~r/^(?i)(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(.+)$/u,
            desc
          ) ->
        [_full, word, rest] = m
        q = Map.get(@word_qty, String.downcase(word), 1.0)
        {q, String.trim(rest)}

      m = Regex.run(~r/^(\d+)\s+(.+)$/u, desc) ->
        [_full, num_s, rest] = m

        case Integer.parse(num_s) do
          {n, _} when n >= 2 ->
            {n * 1.0, String.trim(rest)}

          _ ->
            {1.0, desc}
        end

      true ->
        {1.0, desc}
    end
  end
end
