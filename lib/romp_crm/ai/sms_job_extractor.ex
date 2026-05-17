defmodule RompCrm.Ai.SmsJobExtractor do
  @moduledoc """
  Turns free-form SMS text into one or more **create/update** instructions via the configured
  adapter (Anthropic Claude in production, deterministic stub in tests).

  Production adapters receive `jobs_snapshot` (`Jobs.snapshot_for_sms_ai/0`) so the model can
  compare the SMS against live CRM rows (names, addresses, work text, typos, informal references).

  - `{:ok, %{assistant_sms: String.t() | nil, operations: list}}` where `operations` contains zero or more:
    - `{:create, attrs}` — attrs match `RompCrm.Jobs.create_job/1` (optional **`scheduled_on`**, **`work_items`**, **`materials`**).
    - `{:update_by_id, job_id, patch}` — `RompCrm.Jobs.update_job/2` after validating `job_id`.
    - `{:update, match, patch}` — fallback: resolve via `RompCrm.Jobs.find_job_for_sms_update/1`.
    - `{:attach_photos, job_id, work_item_title_hint, urls}` — download each URL and store under the job (Twilio MMS).
  """

  alias RompCrm.Jobs.Job

  @doc """
  Returns `{:ok, %{assistant_sms: nil | String.t(), operations: list}}` or `{:error, reason}`.

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
    assistant = assistant_from_map(map)

    parsed_ops =
      case Map.get(map, "actions") do
        actions when is_list(actions) ->
          parse_actions(actions)

        nil ->
          case parse_single_action(Map.drop(map, ["assistant_sms"])) do
            {:ok, op} -> {:ok, [op]}
            err -> err
          end

        _ ->
          {:error, :invalid_actions}
      end

    case parsed_ops do
      {:ok, ops} -> finalize_extract(assistant, ops)
      err -> err
    end
  end

  defp assistant_from_map(map) do
    case Map.get(map, "assistant_sms") do
      s when is_binary(s) ->
        s |> String.trim() |> String.slice(0, 480)

      _ ->
        nil
    end
  end

  defp finalize_extract(assistant, ops) do
    cond do
      ops == [] and (assistant == nil or assistant == "") ->
        {:error, :empty_extract}

      true ->
        {:ok, %{assistant_sms: assistant, operations: ops}}
    end
  end

  defp parse_actions([]), do: {:ok, []}

  defp parse_actions(actions) when is_list(actions) do
    case Enum.with_index(actions, 1) do
      [] ->
        {:ok, []}

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

  defp parse_actions(_), do: {:error, :invalid_actions}

  @doc false
  def parse_actions_list(actions) when is_list(actions), do: parse_actions(actions)
  def parse_actions_list(_), do: {:error, :invalid_actions}

  defp parse_single_action(map) when is_map(map) do
    map = stringify_top_level_keys(map)

    intent =
      case Map.get(map, "intent") do
        nil -> infer_intent(map)
        v -> v |> to_string() |> String.trim() |> String.downcase()
      end

    case intent do
      "attach_photo" -> parse_attach_photo_intent(map)
      "update" -> parse_update_intent(map)
      _ -> parse_create_intent(map)
    end
  end

  defp stringify_top_level_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

    defp infer_intent(map) do
    urls = collect_media_urls(map)
    match = Map.get(map, "match")
    updates = Map.get(map, "updates")
    job_id_present? = job_id_present_in_map?(map)

    cond do
      urls != [] and job_id_present? ->
        "attach_photo"

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
        %{} = job_map ->
          job_map

        _ ->
          Map.drop(map, [
            "intent",
            "match",
            "updates",
            "job_id",
            "actions",
            "assistant_sms"
          ])
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
    |> maybe_put_string(:client_email, m["client_email"])
    |> maybe_put_string(:work_description, m["work_description"])
    |> maybe_put_string(:referred_by, m["referred_by"])
    |> maybe_put_string(:notes, m["notes"])
    |> maybe_put_string(:next_action, m["next_action"])
    |> maybe_put_date(:scheduled_on, m["scheduled_on"])
    |> maybe_put_work_items(:work_items, m["work_items"])
    |> maybe_put_materials(:materials, m["materials"])
    |> maybe_put_enum(:priority, m["priority"], Job.priorities())
    |> maybe_put_enum(:status, m["status"], Job.statuses())
  end

  defp maybe_put_date(acc, key, raw) do
    case parse_iso_date(raw) do
      nil -> acc
      %Date{} = d -> Map.put(acc, key, d)
    end
  end

  defp maybe_put_work_items(acc, key, raw) do
    list = normalize_work_items_for_patch(raw)
    if list == [], do: acc, else: Map.put(acc, key, list)
  end

  defp maybe_put_materials(acc, key, raw) do
    list = normalize_materials_for_patch(raw)
    if list == [], do: acc, else: Map.put(acc, key, list)
  end

  defp normalize_work_items_for_patch(nil), do: []

  defp normalize_work_items_for_patch(list) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      row = stringify_top_level_keys(row)
      title = nilify_blank(row["title"])

      if title do
        %{
          "title" => title,
          "sort_order" => Map.get(row, "sort_order") || i,
          "scheduled_on" => parse_iso_date(row["scheduled_on"])
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_work_items_for_patch(_), do: []

  defp normalize_materials_for_patch(nil), do: []

  defp normalize_materials_for_patch(list) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      row = stringify_top_level_keys(row)
      desc = nilify_blank(row["description"])

      if desc do
        wi_id = parse_optional_int(row["job_work_item_id"])
        wi_idx = parse_optional_int(row["work_item_index"])

        %{"description" => desc, "sort_order" => i}
        |> maybe_put_int("job_work_item_id", wi_id)
        |> maybe_put_int("work_item_index", wi_idx)
        |> put_material_quantity_preserved(row["quantity"])
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_materials_for_patch(_), do: []

  # Pass through model-supplied quantity so `Jobs.normalize_material_specs/1` can persist it.
  # Without this, only `description` reached the DB and quantity defaulted to 1 when the prompt
  # kept the count out of the text (e.g. `"quantity":4,"description":"1/2\" elbows"`).
  defp put_material_quantity_preserved(map, raw) do
    case normalize_material_quantity_raw(raw) do
      nil -> map
      q -> Map.put(map, "quantity", q)
    end
  end

  defp normalize_material_quantity_raw(nil), do: nil
  defp normalize_material_quantity_raw(v) when v == "", do: nil

  defp normalize_material_quantity_raw(n) when is_integer(n), do: n
  defp normalize_material_quantity_raw(n) when is_float(n), do: n

  defp normalize_material_quantity_raw(n) when is_binary(n) do
    case String.trim(n) do
      "" -> nil
      s -> s
    end
  end

  defp normalize_material_quantity_raw(_), do: nil

  defp maybe_put_int(map, _key, nil), do: map

  defp maybe_put_int(map, key, n) when is_integer(n) do
    Map.put(map, key, n)
  end

  defp parse_optional_int(nil), do: nil

  defp parse_optional_int(v) when is_integer(v), do: v

  defp parse_optional_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_optional_int(_), do: nil

  defp parse_iso_date(nil), do: nil
  defp parse_iso_date(v) when v == "", do: nil

  defp parse_iso_date(%Date{} = d), do: d

  defp parse_iso_date(v) when is_binary(v) do
    s = String.trim(v)

    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_iso_date(_), do: nil

  defp parse_attach_photo_intent(map) do
    urls = collect_media_urls(map)

    if urls == [] do
      {:error, :attach_photo_missing_url}
    else
      title_hint = nilify_blank(map["work_item_title"])

      case coerce_job_id(Map.get(map, "job_id")) do
        {:ok, job_id} ->
          {:ok, {:attach_photos, job_id, title_hint, urls}}

        :missing ->
          {:error, :attach_photo_needs_job_id}

        {:error, _} ->
          {:error, :invalid_job_id}
      end
    end
  end

  defp collect_media_urls(map) do
    one = nilify_blank(map["media_url"])

    rest =
      case map["media_urls"] do
        list when is_list(list) ->
          list
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    (if(one, do: [one], else: []) ++ rest) |> Enum.uniq()
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

    base = %{
      client_name: client_name,
      address: nilify_blank(m["address"]),
      phone: nilify_blank(m["phone"]),
      client_email: nilify_blank(m["client_email"]),
      work_description: nilify_blank(m["work_description"]),
      priority: coerce_enum(m["priority"], Job.priorities(), :normal),
      status: coerce_enum(m["status"], Job.statuses(), :lead),
      referred_by: nilify_blank(m["referred_by"]),
      notes: nilify_blank(m["notes"]),
      next_action: nilify_blank(m["next_action"])
    }

    extras =
      %{}
      |> put_optional(:scheduled_on, parse_iso_date(m["scheduled_on"]))
      |> put_optional_list(:work_items, normalize_work_items_for_patch(m["work_items"]))
      |> put_optional_list(:materials, normalize_materials_for_patch(m["materials"]))

    Map.merge(base, extras)
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, val), do: Map.put(map, key, val)

  defp put_optional_list(map, _key, []), do: map
  defp put_optional_list(map, key, list) when is_list(list), do: Map.put(map, key, list)

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
