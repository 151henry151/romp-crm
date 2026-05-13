defmodule RompCrm.Jobs do
  import Ecto.Query
  alias RompCrm.Repo
  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobMaterial
  alias RompCrm.Jobs.JobPhoto
  alias RompCrm.Jobs.JobWorkItem

  def subscribe(business_id) when is_integer(business_id) do
    Phoenix.PubSub.subscribe(RompCrm.PubSub, topic(business_id))
  end

  defp topic(business_id), do: "jobs:business:#{business_id}"

  defp work_items_preload_query do
    from wi in JobWorkItem, order_by: [asc: wi.sort_order, asc: wi.id]
  end

  defp materials_preload_query do
    from m in JobMaterial, order_by: [asc: m.sort_order, asc: m.id]
  end

  defp photos_preload_query do
    from p in JobPhoto, order_by: [asc: p.id]
  end

  def list_jobs(business_id) when is_integer(business_id) do
    Repo.all(
      from j in Job,
        where: j.business_id == ^business_id,
        order_by: [
          asc: fragment("CASE ? WHEN 'high' THEN 0 ELSE 1 END", j.priority),
          asc:
            fragment(
              "CASE ? WHEN 'in_progress' THEN 0 WHEN 'pending' THEN 1 WHEN 'lead' THEN 2 ELSE 3 END",
              j.status
            ),
          asc: j.client_name
        ],
        preload: [
          work_items: ^work_items_preload_query(),
          materials: ^materials_preload_query(),
          photos: ^photos_preload_query()
        ]
    )
  end

  def get_job!(id, business_id) when is_integer(id) and is_integer(business_id) do
    Repo.one!(
      from j in Job,
        where: j.id == ^id and j.business_id == ^business_id,
        preload: [
          work_items: ^work_items_preload_query(),
          materials: ^materials_preload_query(),
          photos: ^photos_preload_query()
        ]
    )
  end

  def get_job(id, business_id) when is_integer(id) and is_integer(business_id) do
    Repo.one(
      from j in Job,
        where: j.id == ^id and j.business_id == ^business_id,
        preload: [
          work_items: ^work_items_preload_query(),
          materials: ^materials_preload_query(),
          photos: ^photos_preload_query()
        ]
    )
  end

  @doc false
  def list_upcoming_scheduled_jobs(business_id, within_days \\ 90)
      when is_integer(business_id) and is_integer(within_days) do
    today = Date.utc_today()
    last = Date.add(today, within_days)

    Repo.all(
      from j in Job,
        where: j.business_id == ^business_id,
        where: not is_nil(j.scheduled_on),
        where: j.scheduled_on >= ^today and j.scheduled_on <= ^last,
        order_by: [asc: j.scheduled_on, asc: j.id]
    )
  end

  @doc """
  Returns jobs as plain maps suitable for embedding in an SMS-extraction LLM prompt.

  Each row includes integer `"id"` (database primary key). Fields may be `null` when empty.
  """
  def snapshot_for_sms_ai(business_id) when is_integer(business_id) do
    Enum.map(list_jobs(business_id), fn j ->
      %{
        "id" => j.id,
        "client_name" => j.client_name,
        "address" => j.address,
        "phone" => j.phone,
        "work_description" => j.work_description,
        "notes" => j.notes,
        "next_action" => j.next_action,
        "referred_by" => j.referred_by,
        "status" => Atom.to_string(j.status),
        "priority" => Atom.to_string(j.priority),
        "scheduled_on" => date_to_iso(j.scheduled_on),
        "work_items" =>
          Enum.map(j.work_items || [], fn wi ->
            %{
              "id" => wi.id,
              "title" => wi.title,
              "scheduled_on" => date_to_iso(wi.scheduled_on)
            }
          end),
        "materials" =>
          Enum.map(j.materials || [], fn m ->
            %{
              "id" => m.id,
              "description" => m.description,
              "job_work_item_id" => m.job_work_item_id
            }
          end)
      }
    end)
  end

  defp date_to_iso(nil), do: nil
  defp date_to_iso(%Date{} = d), do: Date.to_iso8601(d)

  def create_job(attrs) when is_map(attrs) do
    attrs = normalize_job_nested_attrs(attrs)
    {mat_action, attrs} = pop_material_specs_attr(attrs)

    case %Job{} |> Job.changeset(attrs) |> Repo.insert() do
      {:ok, job} ->
        job = Repo.preload(job, [:work_items], force: true)
        :ok = sync_material_specs_list(job, mat_action)
        job = Repo.preload(job, [:work_items, :materials, :photos], force: true)
        broadcast(job.business_id, {:created, job})
        {:ok, job}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_job(%Job{} = job, attrs) do
    job = Repo.preload(job, [:work_items, :materials])
    attrs = normalize_job_nested_attrs(attrs)
    attrs = merge_append_only_work_items(job, attrs)
    {mat_action, attrs} = pop_material_specs_attr(attrs)

    case job |> Job.changeset(attrs) |> Repo.update() do
      {:ok, job} ->
        job = Repo.preload(job, [:work_items], force: true)
        :ok = sync_material_specs_list(job, mat_action)
        job = Repo.preload(job, [:work_items, :materials, :photos], force: true)
        broadcast(job.business_id, {:updated, job})
        {:ok, job}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Replaces **job-level** materials (`job_work_item_id` is nil) only; leaves per–work-item rows intact.
  """
  def sync_root_materials_only(%Job{} = job, descriptions) when is_list(descriptions) do
    descriptions =
      descriptions
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Repo.delete_all(
      from m in JobMaterial,
        where: m.job_id == ^job.id and is_nil(m.job_work_item_id)
    )

    Enum.each(Enum.with_index(descriptions), fn {desc, i} ->
      %JobMaterial{}
      |> JobMaterial.changeset(%{
        job_id: job.id,
        job_work_item_id: nil,
        description: desc,
        sort_order: i
      })
      |> Repo.insert!()
    end)

    :ok
  end

  def delete_job(%Job{} = job) do
    bid = job.business_id

    with {:ok, job} <- Repo.delete(job) do
      broadcast(bid, {:deleted, job})
      {:ok, job}
    end
  end

  def change_job(%Job{} = job, attrs \\ %{}) do
    attrs =
      attrs
      |> normalize_job_nested_attrs()
      |> Map.delete("materials")
      |> Map.delete(:materials)

    Job.changeset(job, attrs)
  end

  @doc """
  Materials on the job plus materials tied to work items (deduped by id), sorted for display.
  """
  def materials_combined(%Job{} = job) do
    job = Repo.preload(job, work_items: work_items_preload_query(), materials: materials_preload_query())
    item_by_id = Map.new(job.work_items || [], &{&1.id, &1})

    (job.materials || [])
    |> Enum.sort_by(&{&1.sort_order, &1.id})
    |> Enum.map(fn m ->
      scope =
        case m.job_work_item_id do
          nil ->
            "Job"

          wid ->
            case Map.fetch(item_by_id, wid) do
              {:ok, wi} -> wi.title
              :error -> "Work item ##{wid}"
            end
        end

      %{id: m.id, description: m.description, scope_label: scope}
    end)
  end

  @doc """
  Saves a photo for a job (optionally scoped to a work item). Writes under **`priv/static/uploads/job-photos/`**.
  """
  def add_job_photo(%Job{} = job, business_id, bytes, content_type, work_item_id \\ nil)
      when is_integer(business_id) and is_binary(bytes) do
    if job.business_id != business_id do
      {:error, :wrong_business}
    else
      work_item_id =
        case work_item_id do
          nil -> nil
          id when is_integer(id) -> verify_work_item_belongs(job.id, id)
        end

      if work_item_id == :invalid do
        {:error, :invalid_work_item}
      else
        ext = ext_from_content_type(content_type)
        id_str = Ecto.UUID.generate()
        rel = "uploads/job-photos/#{business_id}/#{job.id}/#{id_str}#{ext}"
        abs = RompCrm.JobUploads.absolute_path(rel)
        :ok = File.mkdir_p(Path.dirname(abs))
        :ok = File.write!(abs, bytes)

        %JobPhoto{}
        |> JobPhoto.changeset(%{
          job_id: job.id,
          job_work_item_id: work_item_id,
          relative_path: rel,
          content_type: content_type,
          byte_size: byte_size(bytes)
        })
        |> Repo.insert()
      end
    end
  end

  defp verify_work_item_belongs(job_id, wi_id) do
    case Repo.get_by(JobWorkItem, id: wi_id, job_id: job_id) do
      nil -> :invalid
      _ -> wi_id
    end
  end

  defp ext_from_content_type(ct) when is_binary(ct) do
    cond do
      String.contains?(ct, "png") -> ".png"
      String.contains?(ct, "gif") -> ".gif"
      String.contains?(ct, "webp") -> ".webp"
      true -> ".jpg"
    end
  end

  defp ext_from_content_type(_), do: ".jpg"

  @doc """
  Fetches **`url`** (Twilio MMS) with account HTTP basic auth and stores via **`add_job_photo/5`**.
  """
  def add_job_photo_from_url(%Job{} = job, business_id, url, work_item_id \\ nil)
      when is_binary(url) do
    account_sid = Application.get_env(:romp_crm, :twilio_account_sid)
    token = Application.get_env(:romp_crm, :twilio_auth_token)

    if is_nil(account_sid) or account_sid == "" or is_nil(token) or token == "" do
      {:error, :missing_twilio_credentials}
    else
      auth = Base.encode64("#{account_sid}:#{token}")

      case Req.get(url, headers: [{"authorization", "Basic #{auth}"}], receive_timeout: 60_000) do
        {:ok, %{status: 200, body: body, headers: h}} when is_binary(body) ->
          ct = content_type_from_headers(h)
          add_job_photo(job, business_id, body, ct, work_item_id)

        {:ok, %{status: s}} ->
          {:error, {:download_failed, s}}

        {:error, reason} ->
          {:error, {:download_failed, reason}}
      end
    end
  end

  defp content_type_from_headers(headers) do
    headers
    |> Enum.find_value("image/jpeg", fn
      {"content-type", v} -> List.first(String.split(v, ";"))
      {"Content-Type", v} -> List.first(String.split(v, ";"))
      _ -> nil
    end)
  end

  defp normalize_job_nested_attrs(attrs) when is_map(attrs) do
    attrs = stringify_keys_shallow(attrs)
    attrs = maybe_add_work_item_sort_orders(attrs)
    attrs = maybe_parse_job_date(attrs, "scheduled_on")
    attrs
  end

  defp maybe_add_work_item_sort_orders(%{"work_items" => wis} = attrs) when is_list(wis) do
    wis =
      wis
      |> Enum.map(&stringify_keys_shallow/1)
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        row
        |> Map.put_new("sort_order", i)
        |> maybe_parse_work_item_date()
      end)

    %{attrs | "work_items" => wis}
  end

  defp maybe_add_work_item_sort_orders(attrs), do: attrs

  # When `cast_assoc(:work_items)` receives only new rows (no `id`), Ecto would replace the
  # association and delete existing line items (`on_replace: :delete`). SMS updates often add a
  # single new task; merge those onto the preloaded rows. If any row carries a persisted `id`,
  # the caller (LLM or UI) is responsible for supplying the full intended list — pass through unchanged.
  defp merge_append_only_work_items(%Job{} = job, attrs) when is_map(attrs) do
    existing = job.work_items || []

    case Map.get(attrs, "work_items") do
      list when is_list(list) and list != [] ->
        if existing != [] and work_items_all_without_persisted_id?(list) do
          preserved = Enum.map(existing, &work_item_to_nested_attrs/1)
          new_rows = Enum.map(list, &strip_work_item_id_for_append/1)
          merged = renumber_work_item_sort_orders(preserved ++ new_rows)
          Map.put(attrs, "work_items", merged)
        else
          attrs
        end

      _ ->
        attrs
    end
  end

  defp work_items_all_without_persisted_id?(list) when is_list(list) do
    Enum.all?(list, fn row -> not work_item_row_has_persisted_id?(row) end)
  end

  defp work_item_row_has_persisted_id?(row) when is_map(row) do
    m = stringify_keys_shallow(row)

    case Map.get(m, "id") do
      nil -> false
      "" -> false
      n when is_integer(n) and n > 0 -> true
      s when is_binary(s) ->
        case Integer.parse(String.trim(s)) do
          {i, _} when i > 0 -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp work_item_to_nested_attrs(%JobWorkItem{} = wi) do
    base = %{
      "id" => wi.id,
      "title" => wi.title,
      "sort_order" => wi.sort_order
    }

    case wi.scheduled_on do
      nil -> base
      %Date{} = d -> Map.put(base, "scheduled_on", Date.to_iso8601(d))
    end
  end

  defp strip_work_item_id_for_append(row) when is_map(row) do
    row
    |> stringify_keys_shallow()
    |> Map.delete("id")
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp renumber_work_item_sort_orders(rows) when is_list(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, i} -> Map.put(row, "sort_order", i) end)
  end

  defp maybe_parse_work_item_date(row) do
    case Map.get(row, "scheduled_on") do
      nil -> row
      "" -> Map.delete(row, "scheduled_on")
      %Date{} = d -> Map.put(row, "scheduled_on", d)
      s when is_binary(s) -> parse_date_into_row(row, String.trim(s))
      _ -> row
    end
  end

  defp parse_date_into_row(row, "") do
    Map.delete(row, "scheduled_on")
  end

  defp parse_date_into_row(row, s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> Map.put(row, "scheduled_on", d)
      _ -> Map.delete(row, "scheduled_on")
    end
  end

  defp maybe_parse_job_date(attrs, key) do
    case Map.get(attrs, key) do
      nil -> attrs
      "" -> Map.delete(attrs, key)
      s when is_binary(s) -> parse_date_into_row(attrs, String.trim(s))
      %Date{} = _ -> attrs
      _ -> attrs
    end
  end

  defp stringify_keys_shallow(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp pop_material_specs_attr(attrs) when is_map(attrs) do
    case Map.pop(attrs, "materials") do
      {nil, rest} ->
        {{:skip}, rest}

      {raw, rest} ->
        {{:sync, normalize_material_specs(raw)}, rest}
    end
  end

  defp normalize_material_specs(raw) when is_list(raw) do
    raw
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      m = stringify_keys_shallow(row)
      desc = m["description"] |> to_string() |> String.trim()

      wi_id =
        case m["job_work_item_id"] do
          nil -> nil
          "" -> nil
          id when is_integer(id) -> id
          id when is_binary(id) ->
            case Integer.parse(String.trim(id)) do
              {n, _} -> n
              :error -> nil
            end

          _ ->
            nil
        end

      wi_index =
        case m["work_item_index"] do
          nil -> nil
          n when is_integer(n) -> n
          n when is_binary(n) ->
            case Integer.parse(String.trim(n)) do
              {x, _} -> x
              :error -> nil
            end

          _ ->
            nil
        end

      %{
        description: desc,
        job_work_item_id: wi_id,
        work_item_index: wi_index,
        sort_order: i
      }
    end)
    |> Enum.filter(fn %{description: d} -> d != "" end)
  end

  defp normalize_material_specs(_), do: []

  defp sync_material_specs_list(_job, {:skip}), do: :ok

  defp sync_material_specs_list(job, {:sync, specs}) do
    Repo.delete_all(from m in JobMaterial, where: m.job_id == ^job.id)

    wis =
      job
      |> Ecto.assoc(:work_items)
      |> Repo.all()
      |> Enum.sort_by(&{&1.sort_order, &1.id})

    Enum.each(specs, fn spec ->
      wi_id =
        cond do
          is_integer(spec.job_work_item_id) ->
            if Enum.any?(wis, &(&1.id == spec.job_work_item_id)),
              do: spec.job_work_item_id,
              else: nil

          is_integer(spec.work_item_index) ->
            case Enum.at(wis, spec.work_item_index) do
              nil -> nil
              wi -> wi.id
            end

          true ->
            nil
        end

      %JobMaterial{}
      |> JobMaterial.changeset(%{
        job_id: job.id,
        job_work_item_id: wi_id,
        description: spec.description,
        sort_order: spec.sort_order
      })
      |> Repo.insert!()
    end)

    :ok
  end

  def find_work_item_id_by_title_substring(%Job{} = job, hint) when is_binary(hint) do
    h = String.downcase(String.trim(hint))
    if h == "", do: nil, else: do_find_wi_title(job.id, h)
  end

  def find_work_item_id_by_title_substring(_, _), do: nil

  defp do_find_wi_title(job_id, h) do
    wis =
      Repo.all(
        from wi in JobWorkItem,
          where: wi.job_id == ^job_id,
          order_by: [asc: wi.sort_order, asc: wi.id]
      )

    Enum.find_value(wis, fn wi ->
      t = wi.title |> to_string() |> String.downcase()
      if String.contains?(t, h) or String.contains?(h, String.slice(t, 0, min(12, String.length(t)))),
        do: wi.id,
        else: nil
    end)
  end

  defp broadcast(business_id, message) do
    Phoenix.PubSub.broadcast(RompCrm.PubSub, topic(business_id), message)
  end

  @doc """
  Picks at most one existing job that best matches SMS `match` clues (from Claude).

  Returns `{:ok, job}`, `{:error, :no_match}`, or `{:error, :ambiguous}` when two jobs score too close.
  """
  def find_job_for_sms_update(match_spec, business_id)
      when is_map(match_spec) and is_integer(business_id) do
    scored =
      list_jobs(business_id)
      |> Enum.map(fn job -> {job, RompCrm.Jobs.SmsMatch.score(job, match_spec)} end)
      |> Enum.filter(fn {_, sc} -> sc >= sms_match_min_score() end)
      |> Enum.sort_by(fn {_, sc} -> -sc end)

    case scored do
      [] ->
        {:error, :no_match}

      [{job, top} | rest] ->
        second =
          case rest do
            [{_, s} | _] -> s
            [] -> 0
          end

        if sms_unique_winner?(top, second), do: {:ok, job}, else: {:error, :ambiguous}
    end
  end

  defp sms_match_min_score, do: 38

  defp sms_unique_winner?(top, second) do
    min = sms_match_min_score()

    cond do
      second == 0 ->
        top >= min

      true ->
        top >= 52 and top >= second + 20
    end
  end

  @doc """
  Returns up to `limit` `{job, score}` pairs for SMS match scoring (highest scores first).
  Used to word clarification texts when matching is ambiguous.
  """
  def top_match_candidates(match_spec, business_id, limit \\ 3)
      when is_map(match_spec) and is_integer(business_id) and is_integer(limit) do
    scored =
      list_jobs(business_id)
      |> Enum.map(fn job -> {job, RompCrm.Jobs.SmsMatch.score(job, match_spec)} end)
      |> Enum.sort_by(fn {_, sc} -> -sc end)
      |> Enum.take(limit)

    scored
  end

  @doc """
  Short SMS asking which job the user meant when heuristic matching ties.

  Uses the top two scored jobs from `match_spec`.
  """
  def ambiguous_match_clarification_sms(match_spec, business_id) when is_map(match_spec) do
    case top_match_candidates(match_spec, business_id, 3) do
      [{j1, _}, {j2, _} | _] ->
        n1 = job_label(j1)
        n2 = job_label(j2)

        "Which one—#{n1} or #{n2}? Reply with that client name."

      _ ->
        "Multiple jobs match—which client did you mean? Be specific."
    end
  end

  defp job_label(%Job{} = j) do
    cn = j.client_name || "Unknown"

    wd =
      case j.work_description do
        nil -> ""
        "" -> ""
        w -> String.slice(String.trim(w), 0, 44)
      end

    if wd != "", do: "#{cn} (#{wd})", else: cn
  end
end
