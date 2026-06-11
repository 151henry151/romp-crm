defmodule RompCrm.SchedulingAgentTest.Sandbox do
  @moduledoc false

  alias RompCrm.Bookings.AvailabilitySummary
  alias RompCrm.Bookings.Escalations
  alias RompCrm.Bookings.Orchestrator
  alias RompCrm.Scheduling.Prefs
  alias RompCrm.Twilio.Phone

  @welcome """
  Welcome to the scheduling agent test workspace.

  This is isolated — nothing here creates real jobs, clients, or customer texts.

  • Left pane: you (the contractor) messaging your RompCRM agent
  • Right pane: your test customer — empty until you start a scheduling conversation

  Example: "I got a call from Sally Pendleton, her number is 802-555-1234 — reach out to schedule a sink repair."

  Then check the right pane for what Sally would receive, and reply as Sally to see how the scheduling agent responds.
  """

  def fresh_state do
    %{
      "version" => 1,
      "next_job_id" => 1,
      "next_client_id" => 1,
      "next_link_id" => 1,
      "next_booking_id" => 1,
      "next_request_id" => 1,
      "jobs" => [],
      "clients" => [],
      "booking_links" => [],
      "bookings" => [],
      "booking_requests" => [],
      "pending_booking_proposal" => nil,
      "pending_escalations" => [],
      "next_escalation_id" => 1,
      "contractor_turns" => [%{"role" => "assistant", "text" => String.trim(@welcome)}],
      "client_turns" => []
    }
  end

  def decode(nil), do: fresh_state()

  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} ->
        map
        |> Map.put_new("pending_escalations", [])
        |> Map.put_new("next_escalation_id", 1)

      _ ->
        fresh_state()
    end
  end

  def encode(state) when is_map(state), do: Jason.encode!(state)

  def append_contractor_turn(state, text) do
    turns = state["contractor_turns"] ++ [%{"role" => "contractor", "text" => text}]
    Map.put(state, "contractor_turns", turns)
  end

  def append_contractor_assistant(state, text) when is_binary(text) and text != "" do
    turns = state["contractor_turns"] ++ [%{"role" => "assistant", "text" => text}]
    Map.put(state, "contractor_turns", turns)
  end

  def append_contractor_assistant(state, _), do: state

  def append_client_turn(state, role, text) when role in ["client", "scheduling_assistant"] do
    turns = state["client_turns"] ++ [%{"role" => role, "text" => text}]
    Map.put(state, "client_turns", turns)
  end

  def contractor_prior_turns(state) do
    state["contractor_turns"]
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"role" => "contractor", "text" => t} -> [{:contractor, t}]
      %{"role" => "assistant", "text" => t} -> [{:assistant, t}]
      _ -> []
    end)
  end

  def client_prior_turns(state) do
    state["client_turns"]
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"role" => "client", "text" => t} -> [{:client, t}]
      %{"role" => "scheduling_assistant", "text" => t} -> [{:assistant, t}]
      _ -> []
    end)
  end

  def jobs_snapshot(state) do
    Enum.map(state["jobs"] || [], &job_snapshot_row/1)
  end

  def clients_snapshot(state) do
    Enum.map(state["clients"] || [], fn c ->
      %{
        id: c["id"],
        client_name: c["client_name"],
        phone: c["phone"],
        client_email: c["client_email"],
        address: c["address"],
        address_line1: c["address_line1"],
        address_line2: c["address_line2"],
        city: c["city"],
        state: c["state"],
        postal_code: c["postal_code"],
        billing_address_different: c["billing_address_different"],
        billing_address_line1: c["billing_address_line1"],
        billing_address_line2: c["billing_address_line2"],
        billing_city: c["billing_city"],
        billing_state: c["billing_state"],
        billing_postal_code: c["billing_postal_code"],
        notes: c["notes"]
      }
    end)
  end

  def bookings_snapshot(state) do
    now = DateTime.utc_now(:second)

    links =
      (state["booking_links"] || [])
      |> Enum.filter(fn l -> l["status"] == "pending" end)
      |> Enum.map(fn l ->
        client = find_client(state, l["client_id"])

        %{
          "booking_link_id" => l["id"],
          "client_id" => l["client_id"],
          "client_name" => client && client["client_name"],
          "client_phone" => l["client_phone_normalized"],
          "job_type_label" => l["job_type_label"],
          "duration_min_minutes" => l["duration_min_minutes"],
          "duration_max_minutes" => l["duration_max_minutes"],
          "expires_at" => nil
        }
      end)

    requests =
      (state["booking_requests"] || [])
      |> Enum.filter(&(&1["status"] == "pending"))
      |> Enum.map(fn r ->
        client = find_client(state, r["client_id"])

        %{
          "booking_request_id" => r["id"],
          "booking_link_id" => r["booking_link_id"],
          "client_id" => r["client_id"],
          "client_name" => client && client["client_name"],
          "availability_text" => r["availability_text"],
          "job_type_label" => r["job_type_label"]
        }
      end)

    bookings =
      (state["bookings"] || [])
      |> Enum.filter(fn b ->
        b["status"] == "confirmed" and DateTime.compare(b["ends_at"], now) == :gt
      end)
      |> Enum.map(fn b ->
        client = find_client(state, b["client_id"])

        %{
          "booking_id" => b["id"],
          "client_id" => b["client_id"],
          "client_name" => client && client["client_name"],
          "starts_at" => DateTime.to_iso8601(b["starts_at"]),
          "ends_at" => DateTime.to_iso8601(b["ends_at"])
        }
      end)

    %{
      "active_booking_links" => links,
      "pending_booking_requests" => requests,
      "upcoming_bookings" => bookings
    }
  end

  def active_client_link(state) do
    (state["booking_links"] || [])
    |> Enum.filter(fn l -> l["status"] == "pending" end)
    |> List.last()
  end

  def client_display_name(state) do
    case active_client_link(state) do
      %{"client_id" => cid} ->
        case find_client(state, cid) do
          %{"client_name" => name} when is_binary(name) and name != "" -> name
          _ -> "Test customer"
        end

      _ ->
        "Test customer"
    end
  end

  def booking_contexts(state, business_id, user_id) do
    case active_client_link(state) do
      nil ->
        []

      link ->
        [build_booking_context(state, link, business_id, user_id)]
    end
  end

  def build_booking_context(state, link, business_id, user_id) do
    client = find_client(state, link["client_id"])
    job = find_job(state, link["job_id"])
    prefs = technician_prefs(user_id)

    summary =
      AvailabilitySummary.compute(
        business_id,
        user_id,
        link["duration_max_minutes"] || 120
      )

    business_name =
      case RompCrm.Businesses.get_business(business_id) do
        %{name: name} -> name
        _ -> "your business"
      end

    %{
      "booking_link_id" => link["id"],
      "business_name" => business_name,
      "client_name" => client && client["client_name"],
      "job_type_label" => link["job_type_label"],
      "duration_min_minutes" => link["duration_min_minutes"],
      "duration_max_minutes" => link["duration_max_minutes"],
      "timezone" => prefs.timezone,
      "booking_url" => Orchestrator.booking_url(link["token"]),
      "open_slots" => summary.open_slots,
      "local_slot_offerings" => summary.local_slot_offerings,
      "intake" => intake_snapshot(link, job),
      "scheduling_memories" => Escalations.memories_snapshot_for_ai(business_id)
    }
  end

  def create_job(state, attrs) when is_map(attrs) do
    id = state["next_job_id"]
    client_name = pick_string(attrs, ["client_name", :client_name]) || "Test lead"

    job = %{
      "id" => id,
      "client_name" => client_name,
      "address" => pick_string(attrs, ["address", :address]),
      "address_line1" => pick_string(attrs, ["address_line1", :address_line1]),
      "address_line2" => pick_string(attrs, ["address_line2", :address_line2]),
      "city" => pick_string(attrs, ["city", :city]),
      "state" => pick_string(attrs, ["state", :state]),
      "postal_code" => pick_string(attrs, ["postal_code", :postal_code]),
      "billing_address_different" => false,
      "billing_address_line1" => nil,
      "billing_address_line2" => nil,
      "billing_city" => nil,
      "billing_state" => nil,
      "billing_postal_code" => nil,
      "phone" => pick_string(attrs, ["phone", :phone]),
      "client_email" => pick_string(attrs, ["client_email", :client_email]),
      "work_description" => pick_string(attrs, ["work_description", :work_description]),
      "customer_comments" => pick_string(attrs, ["customer_comments", :customer_comments]),
      "notes" => pick_string(attrs, ["notes", :notes]),
      "next_action" => pick_string(attrs, ["next_action", :next_action]),
      "referred_by" => pick_string(attrs, ["referred_by", :referred_by]),
      "status" => pick_string(attrs, ["status", :status]) || "lead",
      "priority" => pick_string(attrs, ["priority", :priority]) || "normal",
      "scheduled_on" => pick_string(attrs, ["scheduled_on", :scheduled_on]),
      "scheduled_time" => pick_string(attrs, ["scheduled_time", :scheduled_time]),
      "work_items" => [],
      "materials" => []
    }

    state
    |> Map.update!("jobs", &(&1 ++ [job]))
    |> Map.put("next_job_id", id + 1)
    |> then(&{:ok, &1, job})
  end

  def upsert_client(state, attrs) when is_map(attrs) do
    phone_norm = Phone.normalize_us(pick_string(attrs, ["phone", :phone]) || "")

    existing =
      Enum.find(state["clients"] || [], fn c ->
        if phone_norm != "" do
          Phone.normalize_us(c["phone"] || "") == phone_norm
        else
          same_name?(c["client_name"], pick_string(attrs, ["client_name", :client_name]))
        end
      end)

    if existing do
      {:ok, state, existing}
    else
      id = state["next_client_id"]

      client = %{
        "id" => id,
        "client_name" => pick_string(attrs, ["client_name", :client_name]) || "Test customer",
        "phone" => pick_string(attrs, ["phone", :phone]),
        "client_email" => pick_string(attrs, ["client_email", :client_email]),
        "address" => nil,
        "address_line1" => nil,
        "address_line2" => nil,
        "city" => nil,
        "state" => nil,
        "postal_code" => nil,
        "billing_address_different" => false,
        "billing_address_line1" => nil,
        "billing_address_line2" => nil,
        "billing_city" => nil,
        "billing_state" => nil,
        "billing_postal_code" => nil,
        "notes" => nil
      }

      state =
        state
        |> Map.update!("clients", &(&1 ++ [client]))
        |> Map.put("next_client_id", id + 1)

      {:ok, state, client}
    end
  end

  def create_booking_link(state, attrs) when is_map(attrs) do
    with {:ok, state, client} <- upsert_client(state, attrs) do
      id = state["next_link_id"]
      token = "test-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

      link = %{
        "id" => id,
        "client_id" => client["id"],
        "job_id" => attrs["job_id"] || attrs[:job_id],
        "client_phone_normalized" => Phone.normalize_us(client["phone"] || ""),
        "job_type_label" => pick_string(attrs, ["job_type_label", :job_type_label]) || "service call",
        "duration_min_minutes" => pick_int(attrs, ["duration_min_minutes", :duration_min_minutes], 90),
        "duration_max_minutes" => pick_int(attrs, ["duration_max_minutes", :duration_max_minutes], 120),
        "status" => "pending",
        "token" => token
      }

      state =
        state
        |> Map.update!("booking_links", &(&1 ++ [link]))
        |> Map.put("next_link_id", id + 1)

      {:ok, state, link, client}
    end
  end

  def mark_link_booked(state, link_id) do
    links =
      Enum.map(state["booking_links"] || [], fn l ->
        if l["id"] == link_id, do: Map.put(l, "status", "booked"), else: l
      end)

    Map.put(state, "booking_links", links)
  end

  def store_pending_booking(state, proposal) when is_map(proposal) do
    Map.put(state, "pending_booking_proposal", proposal)
  end

  def clear_pending_booking(state) do
    Map.put(state, "pending_booking_proposal", nil)
  end

  def apply_job_updates(state, link, updates) when is_map(updates) do
    updates = stringify_keys(updates)
    job_id = link["job_id"]

    if job_id && map_size(updates) > 0 do
      jobs =
        Enum.map(state["jobs"] || [], fn job ->
          if job["id"] == job_id, do: patch_job(job, updates), else: job
        end)

      Map.put(state, "jobs", jobs)
    else
      state
    end
  end

  def job_for_link(state, link) do
    Enum.find(state["jobs"] || [], &(&1["id"] == link["job_id"]))
  end

  def client_for_link(state, link) do
    Enum.find(state["clients"] || [], &(&1["id"] == link["client_id"]))
  end

  def service_address_for_job(job) when is_map(job) do
    cond do
      is_binary(job["address"]) and job["address"] != "" -> job["address"]
      job["address_line1"] not in [nil, ""] ->
        [job["address_line1"], job["city"], job["state"], job["postal_code"]]
        |> Enum.filter(&(is_binary(&1) and &1 != ""))
        |> Enum.join(", ")

      true ->
        ""
    end
  end

  defp patch_job(job, updates) do
    job
    |> maybe_put("customer_comments", updates["customer_comments"])
    |> maybe_put("client_email", updates["client_email"] || updates["email"])
    |> maybe_put("address", updates["address"] || updates["service_address"])
    |> maybe_put("work_description", updates["work_description"])
  end

  defp maybe_put(job, key, val) when is_binary(val) and val != "" do
    Map.put(job, key, val)
  end

  defp maybe_put(job, _key, _val), do: job

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  def sync_job_from_booking(state, link_id, starts_at, user_id) do
    link = Enum.find(state["booking_links"] || [], &(&1["id"] == link_id))
    job_id = link && link["job_id"]

    if is_integer(job_id) do
      tz = technician_prefs(user_id).timezone
      local = DateTime.shift_zone!(starts_at, tz)
      date_iso = local |> DateTime.to_date() |> Date.to_iso8601()
      time_hhmm = format_hhmm(local)

      jobs =
        Enum.map(state["jobs"] || [], fn job ->
          if job["id"] == job_id do
            job
            |> Map.put("status", if(job["status"] == "lead", do: "pending", else: job["status"]))
            |> Map.put("scheduled_on", date_iso)
            |> Map.put("scheduled_time", time_hhmm)
          else
            job
          end
        end)

      Map.put(state, "jobs", jobs)
    else
      state
    end
  end

  defp job_snapshot_row(job) do
    %{
      "id" => job["id"],
      "client_name" => job["client_name"],
      "address" => job["address"],
      "address_line1" => job["address_line1"],
      "address_line2" => job["address_line2"],
      "city" => job["city"],
      "state" => job["state"],
      "postal_code" => job["postal_code"],
      "billing_address_different" => job["billing_address_different"],
      "billing_address" => nil,
      "billing_address_line1" => job["billing_address_line1"],
      "billing_address_line2" => job["billing_address_line2"],
      "billing_city" => job["billing_city"],
      "billing_state" => job["billing_state"],
      "billing_postal_code" => job["billing_postal_code"],
      "phone" => job["phone"],
      "client_email" => job["client_email"],
      "work_description" => job["work_description"],
      "customer_comments" => job["customer_comments"],
      "notes" => job["notes"],
      "next_action" => job["next_action"],
      "referred_by" => job["referred_by"],
      "status" => job["status"],
      "priority" => job["priority"],
      "scheduled_on" => job["scheduled_on"],
      "scheduled_time" => job["scheduled_time"],
      "work_items" => job["work_items"] || [],
      "materials" => job["materials"] || []
    }
  end

  defp intake_snapshot(link, job) do
    job = job || %{}

    service_address = job["address"]
    email = job["client_email"]
    comments = job["customer_comments"]

    needs = %{
      "customer_comments" => is_nil(comments),
      "service_address" => is_nil(service_address),
      "email" => is_nil(email),
      "billing_address" => false,
      "any" => is_nil(comments) or is_nil(service_address) or is_nil(email)
    }

    %{
      "job_id" => link["job_id"],
      "on_file" => %{
        "customer_comments" => comments,
        "service_address" => service_address,
        "email" => email,
        "billing_address_different" => false,
        "billing_address" => nil
      },
      "needs" => needs
    }
  end

  defp find_client(state, id) do
    Enum.find(state["clients"] || [], &(&1["id"] == id))
  end

  defp find_job(state, id) do
    Enum.find(state["jobs"] || [], &(&1["id"] == id))
  end

  defp technician_prefs(user_id) do
    case RompCrm.Repo.get(RompCrm.Accounts.User, user_id) do
      %RompCrm.Accounts.User{scheduling_prefs_json: json} when is_binary(json) ->
        Prefs.decode(json)

      _ ->
        Prefs.default()
    end
  end

  defp pick_string(map, keys) do
    Enum.find_value(keys, fn k ->
      case Map.get(map, k) do
        s when is_binary(s) and s != "" -> s
        _ -> nil
      end
    end)
  end

  defp pick_int(map, keys, default) do
    case pick_string(map, keys) do
      nil ->
        Enum.find_value(keys, fn k ->
          case Map.get(map, k) do
            n when is_integer(n) -> n
            _ -> nil
          end
        end) || default

      s ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> default
        end
    end
  end

  defp same_name?(a, b) when is_binary(a) and is_binary(b) do
    norm = fn s -> s |> String.downcase() |> String.trim() end
    norm.(a) != "" and norm.(a) == norm.(b)
  end

  defp same_name?(_, _), do: false

  defp format_hhmm(%DateTime{} = dt) do
    hh = dt.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    mm = dt.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    hh <> ":" <> mm
  end
end
