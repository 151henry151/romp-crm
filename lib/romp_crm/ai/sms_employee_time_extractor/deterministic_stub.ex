defmodule RompCrm.Ai.SmsEmployeeTimeExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double for `SmsEmployeeTimeExtractor`.

  - `STUB_EMP_IN <JSON>` — `{"employee_id": <int>, "clocked_in_at": "<iso>"}` → clock_in action.
  - `STUB_EMP_OUT <JSON>` — `{"employee_id": <int>, "clocked_out_at": "<iso>"}` → clock_out action.
  - `STUB_EMP_LUNCH <JSON>` — `{"employee_id": <int>, "lunch_start_at": "<iso>", "lunch_end_at": "<iso>"}` → lunch action.
  - Any other message → `{"actions": [], "assistant_sms": null}`.
  """
  def extract(raw_message, _employees_snapshot \\ []) when is_binary(raw_message) do
    trimmed = String.trim(raw_message)

    case trimmed do
      <<"STUB_EMP_IN ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{"employee_id" => emp_id, "clocked_in_at" => ts}} ->
            {:ok,
             %{
               "assistant_sms" => "Stub: employee clocked in.",
               "actions" => [
                 %{"intent" => "clock_in", "employee_id" => emp_id, "clocked_in_at" => ts}
               ]
             }}

          {:ok, _} ->
            {:error, :stub_missing_fields}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_EMP_OUT ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, %{"employee_id" => emp_id, "clocked_out_at" => ts}} ->
            {:ok,
             %{
               "assistant_sms" => "Stub: employee clocked out.",
               "actions" => [
                 %{"intent" => "clock_out", "employee_id" => emp_id, "clocked_out_at" => ts}
               ]
             }}

          {:ok, _} ->
            {:error, :stub_missing_fields}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_EMP_LUNCH ", json::binary>> ->
        case Jason.decode(json) do
          {:ok,
           %{
             "employee_id" => emp_id,
             "lunch_start_at" => lunch_start,
             "lunch_end_at" => lunch_end
           }} ->
            {:ok,
             %{
               "assistant_sms" => "Stub: employee lunch recorded.",
               "actions" => [
                 %{
                   "intent" => "lunch",
                   "employee_id" => emp_id,
                   "lunch_start_at" => lunch_start,
                   "lunch_end_at" => lunch_end
                 }
               ]
             }}

          {:ok, _} ->
            {:error, :stub_missing_fields}

          {:error, _} ->
            {:error, :stub_bad_json}
        end

      <<"STUB_JSON ", json::binary>> ->
        case Jason.decode(json) do
          {:ok, payload} -> {:ok, payload}
          {:error, _} -> {:error, :stub_bad_json}
        end

      _ ->
        {:ok, %{"assistant_sms" => nil, "actions" => []}}
    end
  end
end
