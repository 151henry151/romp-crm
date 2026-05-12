defmodule RompCrmWeb.DatetimeLocal do
  @moduledoc """
  Parses values from HTML **`datetime-local`** inputs (`YYYY-MM-DDTHH:mm`, optional seconds).
  """

  @doc """
  Returns **`{:ok, %NaiveDateTime{}}`** or **`{:error, :missing}`** / **`{:error, :invalid}`**.
  """
  def parse(nil), do: {:error, :missing}

  def parse(str) when is_binary(str) do
    str = String.trim(str)

    if str == "" do
      {:error, :missing}
    else
      normalized =
        cond do
          String.contains?(str, " ") ->
            String.replace(str, " ", "T")

          true ->
            str
        end
        |> maybe_append_seconds()

      case NaiveDateTime.from_iso8601(normalized) do
        {:ok, ndt} -> {:ok, ndt}
        _ -> {:error, :invalid}
      end
    end
  end

  defp maybe_append_seconds(s) do
    if Regex.match?(~r/^(\d{4}-\d{2}-\d{2})T(\d{1,2}):(\d{2})$/, s) do
      s <> ":00"
    else
      s
    end
  end
end
