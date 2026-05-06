defmodule JgsCrm.Ai.SmsJobExtractor do
  @moduledoc """
  Turns free-form SMS text into a **create** or **update** instruction via the configured
  adapter (Anthropic Claude in production, deterministic stub in tests).

  - `{:ok, {:create, attrs}}` — attrs match `JgsCrm.Jobs.create_job/1`.
  - `{:ok, {:update, match, patch}}` — resolve job via `JgsCrm.Jobs.find_job_for_sms_update/1`,
    then `JgsCrm.Jobs.update_job/2` with `patch`.
  """

  alias JgsCrm.Jobs.Job

  @doc """
  Returns:

    - `{:ok, {:create, attrs}}` with atom keys for `JgsCrm.Jobs.create_job/1`
    - `{:ok, {:update, match, patch}}` — atom-key patch map for `update_job/2`; match uses string keys
    - `{:error, reason}` otherwise.
  """
  def extract(raw_message) when is_binary(raw_message) do
    mod = Application.get_env(:jgs_crm, :sms_job_extractor_adapter, __MODULE__.Anthropic)

    case mod.extract(raw_message) do
      {:ok, attrs} when is_map(attrs) -> parse_extracted_map(attrs)
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp parse_extracted_map(map) when is_map(map) do
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

    if is_map(match) and is_map(updates) and map_size(updates) > 0 do
      "update"
    else
      "create"
    end
  end

  defp parse_update_intent(map) do
    match = Map.get(map, "match")
    updates = Map.get(map, "updates")

    cond do
      not is_map(match) ->
        {:error, :update_missing_match}

      not is_map(updates) or map_size(updates) == 0 ->
        {:error, :update_missing_updates}

      true ->
        n_match = normalize_match_map(match)

        if map_size(n_match) == 0 do
          {:error, :update_empty_match}
        else
          patch = normalize_update_patch(updates)

          if map_size(patch) == 0 do
            {:error, :update_empty_patch}
          else
            {:ok, {:update, n_match, patch}}
          end
        end
    end
  end

  defp parse_create_intent(map) do
    payload =
      case Map.get(map, "job") do
        %{} = job_map -> job_map
        _ -> Map.drop(map, ["intent", "match", "updates"])
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
