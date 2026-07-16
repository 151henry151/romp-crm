defmodule RompCrm.PrintReports do
  @moduledoc """
  Owner-only printable PDF reports: activity (date range) and customer list.
  """

  import Ecto.Query

  alias RompCrm.Businesses.Business
  alias RompCrm.Clients.Client
  alias RompCrm.DataExport
  alias RompCrm.Employees.Employee
  alias RompCrm.Employees.EmployeeTimeEntry
  alias RompCrm.Jobs.Job
  alias RompCrm.PrintReports.Html
  alias RompCrm.Repo
  alias RompCrm.TimeTracking.TimeEntry

  @doc "Parse report type from settings form params."
  def normalize_report_type(params) when is_map(params) do
    case Map.get(params, "report_type") |> to_string() |> String.trim() do
      "activity" -> {:ok, :activity}
      "customers" -> {:ok, :customers}
      _ -> {:error, :invalid_report_type}
    end
  end

  @doc "Parse inclusive from/to dates. Rejects missing or inverted ranges."
  def normalize_date_range(params) when is_map(params) do
    with {:ok, from} <- parse_date(Map.get(params, "from_date")),
         {:ok, to} <- parse_date(Map.get(params, "to_date")),
         true <- Date.compare(from, to) in [:eq, :lt] do
      {:ok, from, to}
    else
      _ -> {:error, :invalid_date_range}
    end
  end

  defp parse_date(%Date{} = d), do: {:ok, d}

  defp parse_date(raw) when is_binary(raw) do
    case Date.from_iso8601(String.trim(raw)) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error

  @doc "Reuse DataExport ownership rules for workspace selection."
  defdelegate normalize_export_business_ids(user, params), to: DataExport

  @doc """
  Activity report for owned business ids over an inclusive date range.

  Includes open (non-done) pipeline jobs regardless of date.
  """
  def build_activity_report(business_ids, %Date{} = from_date, %Date{} = to_date)
      when is_list(business_ids) do
    businesses = load_businesses(business_ids)
    {range_start, range_end_exclusive} = naive_range(from_date, to_date)
    {utc_start, utc_end_exclusive} = utc_range(from_date, to_date)

    job_entries = load_job_time_entries(business_ids, range_start, range_end_exclusive)
    clock_punches = load_clock_punches(business_ids, range_start, range_end_exclusive)
    new_leads = load_new_leads(business_ids, utc_start, utc_end_exclusive)
    jobs_worked_on = jobs_from_entries(job_entries)
    open_jobs = load_open_jobs(business_ids)
    job_hours = group_job_hours(job_entries)

    %{
      businesses: businesses,
      from_date: from_date,
      to_date: to_date,
      summary: %{
        job_minutes: Enum.reduce(job_hours, 0, fn row, acc -> acc + row.minutes end),
        employee_worked_minutes:
          Enum.reduce(clock_punches, 0, fn row, acc -> acc + (row.worked_minutes || 0) end),
        new_leads_count: length(new_leads),
        jobs_worked_on_count: length(jobs_worked_on)
      },
      job_hours: job_hours,
      clock_punches: clock_punches,
      new_leads: new_leads,
      jobs_worked_on: jobs_worked_on,
      open_jobs: open_jobs
    }
  end

  @doc "Full customer list for owned business ids."
  def build_customer_list(business_ids) when is_list(business_ids) do
    businesses = load_businesses(business_ids)

    customers =
      if business_ids == [] do
        []
      else
        clients =
          Repo.all(
            from c in Client,
              where: c.business_id in ^business_ids,
              order_by: [asc: c.business_id, asc: c.client_name, asc: c.id]
          )

        job_counts =
          Repo.all(
            from j in Job,
              where: j.business_id in ^business_ids and not is_nil(j.client_id),
              group_by: j.client_id,
              select: {j.client_id, count(j.id)}
          )
          |> Map.new()

        biz_names = Map.new(businesses, &{&1.id, &1.name})

        Enum.map(clients, fn c ->
          %{
            id: c.id,
            business_id: c.business_id,
            business_name: Map.get(biz_names, c.business_id, ""),
            client_name: blank_to_dash(c.client_name),
            phone: c.phone,
            client_email: c.client_email,
            address: format_service_address(c),
            billing_address: format_billing_address(c),
            notes: c.notes,
            job_count: Map.get(job_counts, c.id, 0)
          }
        end)
      end

    %{businesses: businesses, customers: customers}
  end

  @doc """
  Build HTML and print to PDF via configured adapter.

  Options: `:from_date`, `:to_date` (activity), `:generated_at` (`DateTime`).
  """
  def render_pdf(type, report, opts \\ []) when type in [:activity, :customers] do
    generated_at = Keyword.get(opts, :generated_at, DateTime.utc_now()) |> DateTime.truncate(:second)
    from_date = Keyword.get(opts, :from_date)
    to_date = Keyword.get(opts, :to_date)

    html =
      case type do
        :activity ->
          Html.activity_document(report, from_date, to_date, generated_at)

        :customers ->
          Html.customers_document(report, generated_at)
      end

    adapter = Application.get_env(:romp_crm, :print_reports_pdf_adapter, __MODULE__.Pdf.Chromic)

    with {:ok, pdf} <- adapter.print_html(html) do
      {:ok, pdf, filename_for(type, from_date, to_date, generated_at)}
    end
  end

  defp filename_for(:activity, %Date{} = from, %Date{} = to, _) do
    "romp-crm-activity-#{Date.to_iso8601(from)}_to_#{Date.to_iso8601(to)}.pdf"
  end

  defp filename_for(:activity, _, _, %DateTime{} = at) do
    "romp-crm-activity-#{Calendar.strftime(at, "%Y-%m-%d")}.pdf"
  end

  defp filename_for(:customers, _, _, %DateTime{} = at) do
    "romp-crm-customers-#{Calendar.strftime(at, "%Y-%m-%d")}.pdf"
  end

  defp load_businesses(business_ids) do
    if business_ids == [] do
      []
    else
      Repo.all(
        from b in Business,
          where: b.id in ^business_ids,
          order_by: [asc: b.name, asc: b.id]
      )
    end
  end

  defp naive_range(%Date{} = from, %Date{} = to) do
    start = NaiveDateTime.new!(from, ~T[00:00:00])
    exclusive = NaiveDateTime.new!(Date.add(to, 1), ~T[00:00:00])
    {start, exclusive}
  end

  defp utc_range(%Date{} = from, %Date{} = to) do
    start = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    exclusive = DateTime.new!(Date.add(to, 1), ~T[00:00:00], "Etc/UTC")
    {start, exclusive}
  end

  defp load_job_time_entries(business_ids, range_start, range_end_exclusive) do
    if business_ids == [] do
      []
    else
      Repo.all(
        from te in TimeEntry,
          join: j in Job,
          on: j.id == te.job_id,
          where: te.business_id in ^business_ids,
          where: te.started_at < ^range_end_exclusive,
          where: is_nil(te.ended_at) or te.ended_at >= ^range_start,
          order_by: [asc: te.business_id, asc: te.started_at, asc: te.id],
          preload: [job: j]
      )
    end
  end

  defp load_clock_punches(business_ids, range_start, range_end_exclusive) do
    if business_ids == [] do
      []
    else
      Repo.all(
        from te in EmployeeTimeEntry,
          join: e in Employee,
          on: e.id == te.employee_id,
          where: te.business_id in ^business_ids,
          where: te.clocked_in_at < ^range_end_exclusive,
          where: is_nil(te.clocked_out_at) or te.clocked_out_at >= ^range_start,
          order_by: [asc: te.business_id, asc: te.clocked_in_at, asc: te.id],
          select: {te, e}
      )
      |> Enum.map(fn {te, emp} ->
        %{
          id: te.id,
          business_id: te.business_id,
          employee_name: emp.name || "Employee ##{emp.id}",
          clocked_in_at: te.clocked_in_at,
          clocked_out_at: te.clocked_out_at,
          lunch_start_at: te.lunch_start_at,
          lunch_end_at: te.lunch_end_at,
          worked_minutes: EmployeeTimeEntry.worked_minutes(te),
          clock_in_kind: te.clock_in_kind,
          clock_out_kind: te.clock_out_kind,
          notes: te.notes
        }
      end)
    end
  end

  defp load_new_leads(business_ids, utc_start, utc_end_exclusive) do
    if business_ids == [] do
      []
    else
      Repo.all(
        from j in Job,
          where: j.business_id in ^business_ids,
          where: j.status == :lead,
          where: j.inserted_at >= ^utc_start and j.inserted_at < ^utc_end_exclusive,
          order_by: [asc: j.business_id, desc: j.inserted_at, asc: j.id]
      )
    end
  end

  defp load_open_jobs(business_ids) do
    if business_ids == [] do
      []
    else
      Repo.all(
        from j in Job,
          where: j.business_id in ^business_ids,
          where: j.status in [:lead, :pending, :in_progress],
          order_by: [asc: j.business_id, asc: j.status, asc: j.scheduled_on, asc: j.id]
      )
    end
  end

  defp jobs_from_entries(entries) do
    entries
    |> Enum.map(& &1.job)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.business_id, &1.client_name || "", &1.id})
  end

  defp group_job_hours(entries) do
    entries
    |> Enum.group_by(& &1.job_id)
    |> Enum.map(fn {job_id, list} ->
      job = hd(list).job
      minutes =
        Enum.reduce(list, 0, fn te, acc ->
          case TimeEntry.duration_minutes(te) do
            nil -> acc
            m -> acc + m
          end
        end)

      %{
        job_id: job_id,
        business_id: job && job.business_id,
        client_name: (job && job.client_name) || "Job ##{job_id}",
        status: job && job.status,
        minutes: minutes,
        entry_count: length(list)
      }
    end)
    |> Enum.sort_by(&{&1.business_id, &1.client_name, &1.job_id})
  end

  defp format_service_address(c) do
    parts =
      [
        c.address_line1,
        c.address_line2,
        [c.city, c.state, c.postal_code]
        |> Enum.reject(&(is_nil(&1) or &1 == ""))
        |> Enum.join(", ")
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    case parts do
      [] -> blank_to_dash(c.address)
      list -> Enum.join(list, ", ")
    end
  end

  defp format_billing_address(%{billing_address_different: true} = c) do
    parts =
      [
        c.billing_address_line1,
        c.billing_address_line2,
        [c.billing_city, c.billing_state, c.billing_postal_code]
        |> Enum.reject(&(is_nil(&1) or &1 == ""))
        |> Enum.join(", ")
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    if parts == [], do: "—", else: Enum.join(parts, ", ")
  end

  defp format_billing_address(_), do: "Same as service"

  defp blank_to_dash(nil), do: "—"
  defp blank_to_dash(""), do: "—"
  defp blank_to_dash(s) when is_binary(s), do: s
end
