defmodule RompCrm.Ai.SmsJobExtractor do
  @moduledoc """
  Turns free-form SMS text into one or more **create/update** instructions via the configured
  adapter (Anthropic Claude in production, deterministic stub in tests).

  Production adapters receive `jobs_snapshot` (`Jobs.snapshot_for_sms_ai/0`) so the model can
  compare the SMS against live CRM rows (names, addresses, work text, typos, informal references).

  - `{:ok, operations}` where `operations` is a non-empty list of:
    - `{:create, attrs}` — attrs match `RompCrm.Jobs.create_job/1`.
    - `{:update_by_id, job_id, patch}` — `RompCrm.Jobs.update_job/2` after validating `job_id`.
    - `{:update, match, patch}` — fallback: resolve via `RompCrm.Jobs.find_job_for_sms_update/1`.
  """

  alias RompCrm.Jobs.Job

  @doc """
  Returns `{:ok, operations}` where `operations` is a non-empty list of normalized
  create/update tuples, or `{:error, reason}`.

  `jobs_snapshot` must be the same list passed to the adapter (for validation after extraction).
  """
  def extract(raw_message, jobs_snapshot \\ [])
      when is_binary(raw_message) and is_list(jobs_snapshot) do
    mod = Application.get_env(:romp_crm, :sms_job_extractor_adapter, __MODULE__.Anthropic)

    case mod.extract(raw_message, jobs_snapshot) do
      {:ok, attrs} when is_map(attrs) -> parse_extracted_payload(attrs)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_extracted_payload(map) when is_map(map) do
    map = stringify_top_level_keys(map)

    case Map.get(map, "actions") do
      actions when is_list(actions) ->
        parse_actions(actions)

      _ ->
        with {:ok, op} <- parse_single_action(map) do
          {:ok, [op]}
        end
    end
  end

  defp parse_actions(actions) when is_list(actions) do
    case Enum.with_index(actions, 1) do
      [] ->
        {:error, :empty_actions}

      indexed ->
        Enum.reduce_while(indexed, {:ok, []}, fn {raw_action, idx}, {:ok, acc} ->
          if is_map(raw_action) do
            case parse_single_action(raw_action) do
              {:ok, op} -> {:cont, {:ok, [op | acc]}}
              {:error, reason} -> {:halt, {:error, {:invalid_action, idx, reason}}}
            end
          else
            {:halt, {:error, {:invalid_action, idx, :not_an_object}}}
          end
        end)
        |> case do
          {:ok, ops} -> {:ok, Enum.reverse(ops)}
          err -> err
        end
    end
  end

  defp parse_single_action(map) when is_map(map) do
    map = stringify_top_level_keys(map)

    intent =
      case Map.get(map, "intent") do
        nil -> infer_intent(map)
        v -> v |> to_string() |> String.trim() |> String.downcase()
      end

    case intent do
      "update" -> parse_update_intent(map)
      _ -> parse_create_intent(map)
    end
  end

  defp stringify_top_level_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp infer_intent(map) do
    match = Map.get(map, "match")
    updates = Map.get(map, "updates")
    job_id_present? = job_id_present_in_map?(map)

    cond do
      job_id_present? and is_map(updates) and map_size(updates) > 0 ->
        "update"

      is_map(match) and is_map(updates) and map_size(updates) > 0 ->
        "update"

      true ->
        "create"
    end
  end

  defp parse_update_intent(map) do
    updates = Map.get(map, "updates")

    cond do
      not is_map(updates) or map_size(updates) == 0 ->
        {:error, :update_missing_updates}

      true ->
        patch = normalize_update_patch(updates)

        cond do
          map_size(patch) == 0 ->
            {:error, :update_empty_patch}

          true ->
            case coerce_job_id(Map.get(map, "job_id")) do
              {:ok, job_id} ->
                {:ok, {:update_by_id, job_id, patch}}

              :missing ->
                resolve_update_via_match(Map.get(map, "match"), patch)

              {:error, _} ->
                {:error, :invalid_job_id}
            end
        end
    end
  end

  defp job_id_present_in_map?(map) do
    case Map.get(map, "job_id") do
      nil -> false
      v when v == "" -> false
      _ -> true
    end
  end

  defp coerce_job_id(nil), do: :missing
  defp coerce_job_id(v) when v == "", do: :missing

  defp coerce_job_id(v) when is_integer(v) and v > 0, do: {:ok, v}

  defp coerce_job_id(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i > 0 -> {:ok, i}
      _ -> {:error, :invalid_job_id}
    end
  end

  defp coerce_job_id(_), do: {:error, :invalid_job_id}

  defp resolve_update_via_match(match, patch) do
    n_match = normalize_match_map(match)

    if map_size(n_match) == 0 do
      {:error, :update_missing_job_id_or_match}
    else
      {:ok, {:update, n_match, patch}}
    end
  end

  defp parse_create_intent(map) do
    payload =
      case Map.get(map, "job") do
        %{} = job_map -> job_map
        _ -> Map.drop(map, ["intent", "match", "updates", "job_id", "actions"])
      end

    {:ok, {:create, normalize_create(payload)}}
  end

  defp normalize_match_map(%{} = match) do
    match
    |> stringify_top_level_keys()
    |> trim_fields()
    |> Map.new(fn {k, v} -> {k, nilify_blank(v)} end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_match_map(_), do: %{}

  @doc false
  def normalize_update_patch(attrs) when is_map(attrs) do
    m =
      attrs
      |> stringify_top_level_keys()
      |> trim_fields()

    %{}
    |> maybe_put_string(:client_name, m["client_name"])
    |> maybe_put_string(:address, m["address"])
    |> maybe_put_string(:phone, m["phone"])
    |> maybe_put_string(:work_description, m["work_description"])
    |> maybe_put_string(:referred_by, m["referred_by"])
    |> maybe_put_string(:notes, m["notes"])
    |> maybe_put_string(:next_action, m["next_action"])
    |> maybe_put_enum(:priority, m["priority"], Job.priorities())
    |> maybe_put_enum(:status, m["status"], Job.statuses())
  end

  defp maybe_put_string(acc, key, v) do
    case nilify_blank(v) do
      nil -> acc
      s -> Map.put(acc, key, s)
    end
  end

  defp maybe_put_enum(acc, key, raw, allowed) do
    case coerce_enum_optional(raw, allowed) do
      nil -> acc
      atom -> Map.put(acc, key, atom)
    end
  end

  defp coerce_enum_optional(raw, allowed) do
    normalized = normalize_enum_string(raw)

    if normalized == "" do
      nil
    else
      Enum.find(allowed, fn atom -> Atom.to_string(atom) == normalized end)
    end
  end

  defp normalize_create(attrs) when is_map(attrs) do
    m =
      attrs
      |> stringify_top_level_keys()
      |> trim_fields()

    client_name =
      if blank?(m["client_name"]) do
        "Lead from SMS"
      else
        String.trim(m["client_name"])
      end

    %{
      client_name: client_name,
      address: nilify_blank(m["address"]),
      phone: nilify_blank(m["phone"]),
      work_description: nilify_blank(m["work_description"]),
      priority: coerce_enum(m["priority"], Job.priorities(), :normal),
      status: coerce_enum(m["status"], Job.statuses(), :lead),
      referred_by: nilify_blank(m["referred_by"]),
      notes: nilify_blank(m["notes"]),
      next_action: nilify_blank(m["next_action"])
    }
  end

  defp trim_fields(map) do
    Map.new(map, fn {k, v} -> {k, trim_val(v)} end)
  end

  defp trim_val(v) when is_binary(v), do: String.trim(v)
  defp trim_val(v), do: v

  defp blank?(v) when v in [nil, ""], do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  defp nilify_blank(v) do
    cond do
      blank?(v) -> nil
      is_binary(v) -> String.trim(v)
      true -> v |> to_string() |> String.trim()
    end
  end

  defp coerce_enum(raw, allowed, default) do
    normalized = normalize_enum_string(raw)

    Enum.find(allowed, fn atom -> Atom.to_string(atom) == normalized end) || default
  end

  defp normalize_enum_string(raw) when is_atom(raw), do: Atom.to_string(raw)

  defp normalize_enum_string(raw) when is_binary(raw) do
    s = raw |> String.trim() |> String.downcase()

    case s do
      "in progress" -> "in_progress"
      other -> other
    end
  end

  defp normalize_enum_string(_), do: ""
end
