defmodule RompCrm.BusinessAuditLogs.Detail do
  @moduledoc false

  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobMaterial
  alias RompCrm.Jobs.JobWorkItem
  alias RompCrm.Jobs.MaterialSmsNormalize

  @scalar_fields ~w(
    client_name address phone work_description notes next_action referred_by
    priority status scheduled_on scheduled_time
  )

  @doc """
  Merges **`summary`**, **`changes`**, and optional SMS bodies into metadata for storage.
  """
  def enrich(metadata, opts \\ []) when is_map(metadata) do
    opts = enrich_opts_to_keyword(opts)

    changes = Keyword.get(opts, :changes, Map.get(metadata, :changes, []))
    changes = List.wrap(changes)

    metadata =
      metadata
      |> Map.put(:changes, changes)
      |> maybe_put(:sms_inbound, Keyword.get(opts, :sms_inbound))
      |> maybe_put(:sms_outbound, Keyword.get(opts, :sms_outbound))

    summary =
      Keyword.get(opts, :summary) ||
        Map.get(metadata, :summary) ||
        summary_from_changes(changes)

    Map.put(metadata, :summary, summary)
  end

  defp enrich_opts_to_keyword(opts) when is_list(opts), do: opts

  defp enrich_opts_to_keyword(opts) when is_map(opts) do
    [
      changes: opt_val(opts, :changes),
      sms_inbound: opt_val(opts, :sms_inbound),
      sms_outbound: opt_val(opts, :sms_outbound),
      summary: opt_val(opts, :summary)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp opt_val(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @doc "Plain map snapshot of a job for before/after diffs (materials, work items, scalars)."
  def job_snapshot(%Job{} = job) do
    mats =
      (job.materials || [])
      |> Enum.sort_by(&{&1.sort_order, &1.id})
      |> Enum.map(&material_map/1)

    wis =
      (job.work_items || [])
      |> Enum.sort_by(&{&1.sort_order, &1.id})
      |> Enum.map(&work_item_map/1)

    scalars =
      Map.new(@scalar_fields, fn f ->
        {f, format_scalar(Map.get(job, String.to_atom(f)))}
      end)

    %{materials: mats, work_items: wis, scalars: scalars}
  end

  @doc """
  Builds **`changes`** from an SMS/API patch (append semantics for nested lists) plus optional before/after snapshots.
  """
  def changes_from_job_patch(%Job{} = job, patch, before_snapshot \\ nil, after_snapshot \\ nil)
      when is_map(patch) do
    patch = stringify_keys(patch)
    from_patch = patch_to_changes(job, patch)
    from_diff = snapshot_diff(before_snapshot, after_snapshot)

    merge_change_lists(from_patch, from_diff)
  end

  @doc "Changes list describing a newly created job (materials, work items, scalars)."
  def changes_for_job_created(%Job{} = job) do
    snap = job_snapshot(job)

    scalar_changes =
      Enum.flat_map(snap.scalars, fn {field, value} ->
        if value in [nil, ""] do
          []
        else
          [%{type: "set", field: field, value: value, job_id: job.id, client_name: job.client_name}]
        end
      end)

    wi_changes =
      Enum.map(snap.work_items, fn wi ->
        %{
          type: "work_item_added",
          job_id: job.id,
          client_name: job.client_name,
          title: wi["title"],
          scheduled_on: wi["scheduled_on"]
        }
      end)

    mat_changes =
      Enum.map(snap.materials, fn m ->
        %{
          type: "material_added",
          job_id: job.id,
          client_name: job.client_name,
          description: m["description"],
          quantity: m["quantity"]
        }
      end)

    scalar_changes ++ wi_changes ++ mat_changes
  end

  @doc "Human-readable one-line summary for CSV export."
  def summary_from_changes(changes) when is_list(changes) do
    changes
    |> Enum.map(&change_sentence/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
    |> case do
      "" -> ""
      s -> String.slice(s, 0, 2000)
    end
  end

  @doc "Format **`changes`** for a spreadsheet column."
  def format_changes_for_csv(changes) when is_list(changes) do
    changes
    |> Enum.map(&change_sentence/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" | ")
  end

  @doc "Decode stored metadata JSON to a map."
  def decode_metadata(nil), do: %{}

  def decode_metadata(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = m} -> m
      _ -> %{}
    end
  end

  def decode_metadata(%{} = m), do: m
  def decode_metadata(_), do: %{}

  defp patch_to_changes(%Job{} = job, patch) do
    scalar =
      Enum.flat_map(@scalar_fields, fn field ->
        if Map.has_key?(patch, field) do
          [%{type: "set", field: field, value: format_scalar(Map.get(patch, field)), job_id: job.id, client_name: job.client_name}]
        else
          []
        end
      end)

    materials =
      case Map.get(patch, "materials") do
        list when is_list(list) ->
          Enum.map(list, fn row ->
            row = stringify_keys(row)
            desc = row["description"] |> to_string() |> String.trim()
            explicit = Map.get(row, "quantity")
            {qty, desc_norm} = MaterialSmsNormalize.quantity_and_description(desc, explicit)

            %{
              type: "material_added",
              job_id: job.id,
              client_name: job.client_name,
              description: desc_norm,
              quantity: qty
            }
          end)
          |> Enum.reject(fn %{description: d} -> d == "" end)

        _ ->
          []
      end

    work_items =
      case Map.get(patch, "work_items") do
        list when is_list(list) ->
          Enum.map(list, fn row ->
            row = stringify_keys(row)
            title = row["title"] |> to_string() |> String.trim()

            if title == "" do
              nil
            else
              %{
                type: "work_item_added",
                job_id: job.id,
                client_name: job.client_name,
                title: title,
                scheduled_on: format_scalar(Map.get(row, "scheduled_on"))
              }
            end
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    scalar ++ materials ++ work_items
  end

  defp snapshot_diff(nil, _), do: []
  defp snapshot_diff(_, nil), do: []

  defp snapshot_diff(before, after_snap) do
    before_m = Map.new(before.materials, &{&1["id"], &1})
    after_m = Map.new(after_snap.materials, &{&1["id"], &1})

    added_mats =
      after_snap.materials
      |> Enum.filter(fn m -> not Map.has_key?(before_m, m["id"]) end)
      |> Enum.map(fn m ->
        %{
          type: "material_added",
          material_id: m["id"],
          description: m["description"],
          quantity: m["quantity"]
        }
      end)

    removed_mats =
      before.materials
      |> Enum.filter(fn m -> not Map.has_key?(after_m, m["id"]) end)
      |> Enum.map(fn m ->
        %{
          type: "material_removed",
          material_id: m["id"],
          description: m["description"],
          quantity: m["quantity"]
        }
      end)

    updated_mats =
      Enum.flat_map(after_snap.materials, fn am ->
        case Map.get(before_m, am["id"]) do
          nil ->
            []

          bm ->
            if material_row_equal?(bm, am) do
              []
            else
              [
                %{
                  type: "material_updated",
                  material_id: am["id"],
                  before: %{description: bm["description"], quantity: bm["quantity"]},
                  after_value: %{description: am["description"], quantity: am["quantity"]}
                }
              ]
            end
        end
      end)

    {wi_added, wi_removed} = work_item_diff(before.work_items, after_snap.work_items)
    scalar_diff = scalar_snapshot_diff(before.scalars, after_snap.scalars)

    added_mats ++ removed_mats ++ updated_mats ++ wi_added ++ wi_removed ++ scalar_diff
  end

  defp work_item_diff(before_list, after_list) do
    before_ids = MapSet.new(before_list, & &1["id"])
    after_ids = MapSet.new(after_list, & &1["id"])

    added =
      after_list
      |> Enum.filter(fn wi -> not MapSet.member?(before_ids, wi["id"]) end)
      |> Enum.map(fn wi ->
        %{type: "work_item_added", work_item_id: wi["id"], title: wi["title"], scheduled_on: wi["scheduled_on"]}
      end)

    removed =
      before_list
      |> Enum.filter(fn wi -> not MapSet.member?(after_ids, wi["id"]) end)
      |> Enum.map(fn wi ->
        %{type: "work_item_removed", work_item_id: wi["id"], title: wi["title"]}
      end)

    {added, removed}
  end

  defp scalar_snapshot_diff(before, after_snap) do
    Enum.flat_map(@scalar_fields, fn field ->
      b = Map.get(before, field)
      a = Map.get(after_snap, field)

      if b == a or (blank?(b) and blank?(a)) do
        []
      else
        [%{type: "set", field: field, before: b, after_value: a}]
      end
    end)
  end

  defp merge_change_lists(a, b) do
    Enum.reduce(b, a, fn ch, acc ->
      if Enum.any?(acc, &change_same_event?(&1, ch)), do: acc, else: acc ++ [ch]
    end)
  end

  defp change_same_event?(x, y) do
    x[:type] == y[:type] and
      x[:material_id] == y[:material_id] and
      x[:description] == y[:description] and
      x[:field] == y[:field]
  end

  defp material_row_equal?(a, b) do
    a["description"] == b["description"] and a["quantity"] == b["quantity"]
  end

  defp material_map(%JobMaterial{} = m) do
    %{
      "id" => m.id,
      "description" => m.description,
      "quantity" => m.quantity,
      "completed" => m.completed,
      "unit_price" => m.unit_price
    }
  end

  defp work_item_map(%JobWorkItem{} = wi) do
    %{
      "id" => wi.id,
      "title" => wi.title,
      "scheduled_on" => format_scalar(wi.scheduled_on),
      "completed" => wi.completed
    }
  end

  defp format_scalar(nil), do: nil
  defp format_scalar(%Date{} = d), do: Date.to_iso8601(d)
  defp format_scalar(%Time{} = t), do: Time.to_string(t)
  defp format_scalar(v) when is_atom(v), do: Atom.to_string(v)
  defp format_scalar(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp format_scalar(v) when is_integer(v), do: to_string(v)
  defp format_scalar(v) when is_binary(v), do: String.trim(v)
  defp format_scalar(v), do: to_string(v)

  defp change_sentence(%{type: "material_added"} = c) do
    job = job_prefix(c)
    qty = c[:quantity] || c["quantity"] || 1
    desc = c[:description] || c["description"] || "item"
    "#{job}Added material #{format_qty(qty)}× #{desc}"
  end

  defp change_sentence(%{type: "material_removed"} = c) do
    job = job_prefix(c)
    qty = c[:quantity] || c["quantity"] || 1
    desc = c[:description] || c["description"] || "item"
    "#{job}Removed material #{format_qty(qty)}× #{desc}"
  end

  defp change_sentence(%{type: "material_updated"} = c) do
    b = c[:before] || c["before"] || %{}
    a = c[:after_value] || c["after_value"] || c[:after] || c["after"] || %{}
    mid = c[:material_id] || c["material_id"]

    "Updated material ##{mid}: #{format_qty(b[:quantity] || b["quantity"])}× #{b[:description] || b["description"]} → #{format_qty(a[:quantity] || a["quantity"])}× #{a[:description] || a["description"]}"
  end

  defp change_sentence(%{type: "work_item_added"} = c) do
    job = job_prefix(c)
    title = c[:title] || c["title"] || "task"
    "#{job}Added work item: #{title}"
  end

  defp change_sentence(%{type: "work_item_removed"} = c) do
    title = c[:title] || c["title"] || "task"
    "Removed work item: #{title}"
  end

  defp change_sentence(%{type: "set", field: field, value: value} = c) when not is_nil(value) do
    job = job_prefix(c)
    "#{job}Set #{field} to #{inspect_value(value)}"
  end

  defp change_sentence(%{type: "set", field: field, before: before, after: after_val} = c) do
    job = job_prefix(c)
    "#{job}Changed #{field} from #{inspect_value(before)} to #{inspect_value(after_val)}"
  end

  defp change_sentence(%{type: "time_clocked_in"} = c) do
    name = c[:job_client_name] || c["job_client_name"] || "job"
    at = c[:started_at] || c["started_at"] || ""
    "Clocked in on #{name} at #{at}"
  end

  defp change_sentence(%{type: "time_clocked_out"} = c) do
    name = c[:job_client_name] || c["job_client_name"] || "job"
    "Clocked out on #{name}"
  end

  defp change_sentence(%{type: "employee_time"} = c) do
    name = c[:employee_name] || c["employee_name"] || "employee"
    action = c[:action] || c["action"] || "update"
    "#{action} for employee #{name}"
  end

  defp change_sentence(%{type: "reminder_scheduled"} = c) do
    body = c[:body] || c["body"] || "reminder"
    at = c[:fire_at] || c["fire_at"] || ""
    "Scheduled reminder: #{body} at #{at}"
  end

  defp change_sentence(%{type: "photos_attached"} = c) do
    job = job_prefix(c)
    saved = c[:saved] || c["saved"] || 0
    "#{job}Attached #{saved} photo(s)"
  end

  defp change_sentence(%{type: "job_deleted"} = c) do
    job = job_prefix(c)
    "#{job}Deleted job"
  end

  defp change_sentence(%{type: "root_materials_replaced"} = c) do
    job = job_prefix(c)
    lines = c[:lines] || c["lines"] || []
    "#{job}Replaced job-level materials list (#{length(lines)} line(s))"
  end

  defp change_sentence(_), do: ""

  defp job_prefix(c) do
    cid = c[:client_name] || c["client_name"]
    jid = c[:job_id] || c["job_id"]

    cond do
      is_binary(cid) and cid != "" and jid -> "Job ##{jid} (#{cid}): "
      jid -> "Job ##{jid}: "
      is_binary(cid) and cid != "" -> "Job (#{cid}): "
      true -> ""
    end
  end

  defp format_qty(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_qty(n) when is_integer(n), do: to_string(n)
  defp format_qty(n) when is_binary(n), do: n
  defp format_qty(_), do: "1"

  defp inspect_value(nil), do: "(empty)"
  defp inspect_value(v), do: to_string(v)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp blank?(nil), do: true
  defp blank?(v) when v in ["", nil], do: true
  defp blank?(_), do: false
end
