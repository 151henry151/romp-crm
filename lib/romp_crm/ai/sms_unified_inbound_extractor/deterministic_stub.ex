defmodule RompCrm.Ai.SmsUnifiedInboundExtractor.DeterministicStub do
  @moduledoc false

  @doc """
  Test double for **`SmsUnifiedInboundExtractor`**.

  Recognizes the same **`STUB_*`** prefixes used across legacy stubs so webhook integration tests stay deterministic:

  * **`STUB_TIME_IN`** / **`STUB_TIME_OUT`** → **`time_actions`**
  * **`STUB_EMP_IN`** / **`STUB_EMP_OUT`** / **`STUB_EMP_LUNCH`** → **`employee_actions`**
  * **`STUB_UPDATE`** → **`job_actions`**
  * **`STUB_JSON`** → full unified JSON passthrough
  * **`STUB_CLARIFY`** → empty ops + clarification text
  * default → single job **create** (mirrors job deterministic stub default)

  Snapshots and **`prior_turns`** passed into **`extract/5`** are ignored (tests vary snapshots externally).
  """
  def extract(raw_message, _jobs \\ [], _open_te \\ [], _emps \\ [], _prior \\ [], opts \\ [])
      when is_binary(raw_message) do
    trimmed = String.trim(raw_message)
    pending = Keyword.get(opts, :pending_context, %{}) || %{}

    result =
      cond do
        String.starts_with?(trimmed, "STUB_TIME_IN ") ->
          json = String.trim(String.replace(trimmed, "STUB_TIME_IN ", ""))
          stub_time_in(json)

        String.starts_with?(trimmed, "STUB_TIME_OUT ") ->
          json = String.trim(String.replace(trimmed, "STUB_TIME_OUT ", ""))
          stub_time_out(json)

        String.starts_with?(trimmed, "STUB_EMP_IN ") ->
          json = String.trim(String.replace(trimmed, "STUB_EMP_IN ", ""))
          stub_emp_in(json)

        String.starts_with?(trimmed, "STUB_EMP_OUT ") ->
          json = String.trim(String.replace(trimmed, "STUB_EMP_OUT ", ""))
          stub_emp_out(json)

        String.starts_with?(trimmed, "STUB_EMP_LUNCH ") ->
          json = String.trim(String.replace(trimmed, "STUB_EMP_LUNCH ", ""))
          stub_emp_lunch(json)

        String.starts_with?(trimmed, "STUB_UPDATE ") ->
          json = String.trim(String.replace(trimmed, "STUB_UPDATE ", ""))
          stub_update(json)

        String.starts_with?(trimmed, "STUB_JSON ") ->
          json = String.trim(String.replace(trimmed, "STUB_JSON ", ""))
          stub_json(json)

        String.starts_with?(trimmed, "STUB_CLARIFY ") ->
          msg = String.trim(String.replace(trimmed, "STUB_CLARIFY ", ""))

          {:ok,
           %{
             "assistant_sms" => if(msg != "", do: msg, else: "Which job did you mean?"),
             "turn_intent" => "normal",
             "job_actions" => [],
             "time_actions" => [],
             "employee_actions" => [],
             "reminder_actions" => [],
             "proposed_job_creates" => [],
             "image_kind" => "none"
           }}

        String.starts_with?(trimmed, "STUB_PROPOSE ") ->
          json = String.trim(String.replace(trimmed, "STUB_PROPOSE ", ""))
          stub_propose(json)

        true ->
          {:ok, default_create(trimmed)}
      end

    with {:ok, map} <- result do
      {:ok, maybe_force_setup_intent(map, pending)}
    end
  end

  # When a setup session is active, free-form stub defaults (default_create) are
  # treated as setup answers — production Anthropic uses pending_context the same way.
  defp maybe_force_setup_intent(map, pending) when is_map(map) and is_map(pending) do
    setup_active? =
      Map.get(pending, "scheduling_setup_active") == true or
        Map.get(pending, :scheduling_setup_active) == true

    explicit_intent? =
      is_binary(Map.get(map, "turn_intent")) and map["turn_intent"] not in ["", "normal"]

    cond do
      setup_active? and not explicit_intent? and default_create_shape?(map) ->
        map
        |> Map.put("turn_intent", "scheduling_setup_reply")
        |> Map.put("job_actions", [])
        |> Map.put("booking_actions", [])
        |> Map.put("time_actions", [])
        |> Map.put("employee_actions", [])
        |> Map.put("reminder_actions", [])

      true ->
        Map.put_new(map, "turn_intent", "normal")
    end
  end

  defp maybe_force_setup_intent(map, _), do: Map.put_new(map, "turn_intent", "normal")

  defp default_create_shape?(%{
         "job_actions" => [%{"intent" => "create", "job" => %{"client_name" => "Test SMS Lead"}}]
       }),
       do: true

  defp default_create_shape?(_), do: false

  defp stub_time_in(json) do
    case Jason.decode(json) do
      {:ok, %{"job_id" => job_id, "started_at" => started_at}} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: clocked in.",
           "job_actions" => [],
           "time_actions" => [
             %{"intent" => "clock_in", "job_id" => job_id, "started_at" => started_at}
           ],
           "employee_actions" => [],
           "reminder_actions" => []
         }}

      {:ok, _} ->
        {:error, :stub_missing_fields}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_time_out(json) do
    case Jason.decode(json) do
      {:ok, %{"job_id" => job_id, "ended_at" => ended_at}} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: clocked out.",
           "job_actions" => [],
           "time_actions" => [
             %{"intent" => "clock_out", "job_id" => job_id, "ended_at" => ended_at}
           ],
           "employee_actions" => [],
           "reminder_actions" => []
         }}

      {:ok, _} ->
        {:error, :stub_missing_fields}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_emp_in(json) do
    case Jason.decode(json) do
      {:ok, %{"employee_id" => employee_id, "clocked_in_at" => clocked_in_at}} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: employee clocked in.",
           "job_actions" => [],
           "time_actions" => [],
           "employee_actions" => [
             %{
               "intent" => "clock_in",
               "employee_id" => employee_id,
               "clocked_in_at" => clocked_in_at
             }
           ],
           "reminder_actions" => []
         }}

      {:ok, _} ->
        {:error, :stub_missing_fields}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_emp_out(json) do
    case Jason.decode(json) do
      {:ok, %{"employee_id" => employee_id, "clocked_out_at" => clocked_out_at}} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: employee clocked out.",
           "job_actions" => [],
           "time_actions" => [],
           "employee_actions" => [
             %{
               "intent" => "clock_out",
               "employee_id" => employee_id,
               "clocked_out_at" => clocked_out_at
             }
           ],
           "reminder_actions" => []
         }}

      {:ok, _} ->
        {:error, :stub_missing_fields}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_emp_lunch(json) do
    case Jason.decode(json) do
      {:ok,
       %{
         "employee_id" => employee_id,
         "lunch_start_at" => lunch_start_at,
         "lunch_end_at" => lunch_end_at
       }} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: lunch.",
           "job_actions" => [],
           "time_actions" => [],
           "employee_actions" => [
             %{
               "intent" => "lunch",
               "employee_id" => employee_id,
               "lunch_start_at" => lunch_start_at,
               "lunch_end_at" => lunch_end_at
             }
           ],
           "reminder_actions" => []
         }}

      {:ok, _} ->
        {:error, :stub_missing_fields}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_update(json) do
    case Jason.decode(json) do
      {:ok, %{"job_id" => job_id, "updates" => %{} = updates}} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: updated job.",
           "job_actions" => [
             %{"intent" => "update", "job_id" => job_id, "updates" => updates}
           ],
           "time_actions" => [],
           "employee_actions" => [],
           "reminder_actions" => []
         }}

      {:ok, %{"match" => %{} = match, "updates" => %{} = updates}} ->
        {:ok,
         %{
           "assistant_sms" => "Stub: matched update.",
           "job_actions" => [
             %{"intent" => "update", "match" => match, "updates" => updates}
           ],
           "time_actions" => [],
           "employee_actions" => [],
           "reminder_actions" => []
         }}

      {:ok, _} ->
        {:error, :stub_missing_job_id_or_match_updates}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_propose(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} ->
        {:ok,
         map
         |> Map.put_new("job_actions", [])
         |> Map.put_new("time_actions", [])
         |> Map.put_new("employee_actions", [])
         |> Map.put_new("reminder_actions", [])
         |> Map.put_new("proposed_job_creates", [])
         |> Map.put_new("image_kind", "sms_screenshot")}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp stub_json(rest) do
    json = json_from_stub_rest(rest)

    case Jason.decode(json) do
      {:ok, %{} = map} ->
        map =
          map
          |> lift_legacy_actions_key()
          |> Map.put_new("turn_intent", "normal")
          |> Map.put_new("job_actions", [])
          |> Map.put_new("time_actions", [])
          |> Map.put_new("employee_actions", [])
          |> Map.put_new("reminder_actions", [])
          |> Map.put_new("booking_actions", [])

        {:ok, map}

      {:error, _} ->
        {:error, :stub_bad_json}
    end
  end

  defp lift_legacy_actions_key(%{"job_actions" => _} = m), do: m

  defp json_from_stub_rest(rest) do
    case :binary.match(rest, "{") do
      {pos, _} -> rest |> String.slice(pos..-1//1) |> String.trim()
      :nomatch -> String.trim(rest)
    end
  end

  defp lift_legacy_actions_key(%{"actions" => actions} = m) when is_list(actions) do
    Map.put(m, "job_actions", actions)
  end

  defp lift_legacy_actions_key(m), do: m

  defp default_create(trimmed) do
    %{
      "assistant_sms" => "Added lead from SMS.",
      "turn_intent" => "normal",
      "job_actions" => [
        %{
          "intent" => "create",
          "job" => %{
            "client_name" => "Test SMS Lead",
            "address" => nil,
            "phone" => nil,
            "client_email" => nil,
            "work_description" => String.slice(trimmed, 0, 500),
            "priority" => "normal",
            "status" => "lead",
            "referred_by" => nil,
            "notes" => nil,
            "next_action" => nil
          }
        }
      ],
      "time_actions" => [],
      "employee_actions" => [],
      "reminder_actions" => [],
      "proposed_job_creates" => [],
      "image_kind" => "none"
    }
  end
end
