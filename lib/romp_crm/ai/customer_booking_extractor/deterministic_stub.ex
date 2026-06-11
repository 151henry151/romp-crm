defmodule RompCrm.Ai.CustomerBookingExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double for **`CustomerBookingExtractor`**. Recognized prefixes:

  * **`STUB_BOOK <json>`** — JSON passthrough, defaults `action.type` to `hard_booking`
  * **`STUB_SOFT <json>`** — JSON passthrough, defaults `action.type` to `soft_availability`
  * **`STUB_CLARIFY <json>`** — reply only (no action, no resolved link unless given)
  * default — friendly reply, no action, resolves to the single context when only one exists
  """
  def extract(raw_message, booking_contexts \\ [], _prior_turns \\ [], _opts \\ [])
      when is_binary(raw_message) do
    trimmed = String.trim(raw_message)

    cond do
      String.starts_with?(trimmed, "STUB_BOOK ") ->
        passthrough(String.replace_prefix(trimmed, "STUB_BOOK ", ""))

      String.starts_with?(trimmed, "STUB_SOFT ") ->
        passthrough(String.replace_prefix(trimmed, "STUB_SOFT ", ""))

      String.starts_with?(trimmed, "STUB_CLARIFY ") ->
        passthrough(String.replace_prefix(trimmed, "STUB_CLARIFY ", ""))

      true ->
        resolved =
          case booking_contexts do
            [%{"booking_link_id" => id}] -> id
            _ -> nil
          end

        {:ok,
         %{
           "reply_sms" => "Thanks! We'll follow up shortly.",
           "resolved_booking_link_id" => resolved,
           "action" => nil
         }}
    end
  end

  defp passthrough(json) do
    case Jason.decode(String.trim(json)) do
      {:ok, %{} = map} ->
        {:ok,
         map
         |> Map.put_new("resolved_booking_link_id", nil)
         |> Map.put_new("action", nil)}

      _ ->
        {:error, :stub_bad_json}
    end
  end
end
