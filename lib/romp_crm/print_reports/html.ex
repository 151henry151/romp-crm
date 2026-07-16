defmodule RompCrm.PrintReports.Html do
  @moduledoc false

  @doc "Full HTML document for the activity PDF."
  def activity_document(report, from_date, to_date, _generated_at) do
    range = "#{format_date(from_date)} – #{format_date(to_date)}"
    headline = "Report for #{range}"

    body = """
    <header class="masthead">
      <h1>#{esc(headline)}</h1>
    </header>

    <section class="summary">
      <div class="stat"><span class="num">#{format_minutes(report.summary.job_minutes)}</span><span class="lbl">Job hours</span></div>
      <div class="stat"><span class="num">#{format_minutes(report.summary.employee_worked_minutes)}</span><span class="lbl">Clocked work</span></div>
    </section>

    #{section("Job hours", job_hours_table(report.job_hours))}
    #{section("Clock punches", clock_table(report.clock_punches))}
    #{section("Jobs", jobs_simple_table(report.jobs, include_schedule: true))}
    """

    wrap(headline, body)
  end

  @doc "Full HTML document for the customer list PDF."
  def customers_document(report, _generated_at) do
    body = """
    <header class="masthead">
      <h1>Customer list</h1>
    </header>

    #{customers_table(report.customers)}
    """

    wrap("Customer list", body)
  end

  defp wrap(title, body) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <title>#{esc(title)}</title>
      <style>#{css()}</style>
    </head>
    <body>
    #{body}
    </body>
    </html>
    """
  end

  defp css do
    """
    @page { size: letter; margin: 0.6in 0.65in; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: #1a2332;
      font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, "Times New Roman", serif;
      font-size: 10.5pt;
      line-height: 1.45;
      background: #fff;
    }
    h1 {
      margin: 0 0 0.35rem;
      font-size: 18pt;
      font-weight: 700;
      letter-spacing: -0.02em;
      color: #0b1c2c;
    }
    h2 {
      margin: 1.4rem 0 0.45rem;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 11pt;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: #0b3d5c;
      border-bottom: 1.5pt solid #0b3d5c;
      padding-bottom: 0.25rem;
    }
    .summary {
      display: flex;
      gap: 0.75rem;
      margin: 1.1rem 0 0.5rem;
      padding: 0.75rem 0;
      border-top: 1pt solid #cbd5e1;
      border-bottom: 1pt solid #cbd5e1;
    }
    .stat { flex: 1; text-align: center; }
    .stat .num {
      display: block;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 16pt;
      font-weight: 700;
      color: #0b1c2c;
    }
    .stat .lbl {
      display: block;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 8pt;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: #64748b;
      margin-top: 0.15rem;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 0.35rem 0 0.75rem;
      font-size: 9.5pt;
    }
    th, td {
      text-align: left;
      padding: 0.35rem 0.4rem;
      vertical-align: top;
      border-bottom: 0.5pt solid #e2e8f0;
    }
    th {
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 8pt;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #475569;
      font-weight: 600;
      border-bottom: 1pt solid #94a3b8;
    }
    tr:nth-child(even) td { background: #f8fafc; }
    .empty {
      color: #64748b;
      font-style: italic;
      margin: 0.4rem 0 0.9rem;
    }
    .customer {
      break-inside: avoid;
      margin: 0 0 0.85rem;
      padding: 0.55rem 0.65rem;
      border: 0.75pt solid #cbd5e1;
      border-left: 3pt solid #0b3d5c;
    }
    .customer h3 {
      margin: 0 0 0.25rem;
      font-size: 12pt;
      color: #0b1c2c;
    }
    .customer dl {
      margin: 0;
      display: grid;
      grid-template-columns: 7rem 1fr;
      gap: 0.15rem 0.5rem;
      font-size: 9.5pt;
    }
    .customer dt {
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 8pt;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: #64748b;
    }
    .customer dd { margin: 0; color: #1a2332; }
    """
  end

  defp section(title, inner) do
    "<section><h2>#{esc(title)}</h2>#{inner}</section>"
  end

  defp job_hours_table([]), do: ~s(<p class="empty">No job hours in this range.</p>)

  defp job_hours_table(rows) do
    body =
      Enum.map_join(rows, "\n", fn row ->
        """
        <tr>
          <td>#{esc(row.client_name)}</td>
          <td>#{esc(status_label(row.status))}</td>
          <td>#{esc(format_minutes(row.minutes))}</td>
          <td>#{row.entry_count}</td>
        </tr>
        """
      end)

    """
    <table>
      <thead><tr><th>Client / job</th><th>Status</th><th>Hours</th><th>Entries</th></tr></thead>
      <tbody>#{body}</tbody>
    </table>
    """
  end

  defp clock_table([]), do: ~s(<p class="empty">No clock punches in this range.</p>)

  defp clock_table(rows) do
    body =
      Enum.map_join(rows, "\n", fn row ->
        """
        <tr>
          <td>#{esc(row.employee_name)}</td>
          <td>#{esc(format_naive(row.clocked_in_at))}</td>
          <td>#{esc(format_naive(row.clocked_out_at) || "Open")}</td>
          <td>#{esc(format_minutes(row.worked_minutes))}</td>
          <td>#{esc(kind_label(row.clock_in_kind))} / #{esc(kind_label(row.clock_out_kind))}</td>
        </tr>
        """
      end)

    """
    <table>
      <thead><tr><th>Employee</th><th>In</th><th>Out</th><th>Worked</th><th>Kind</th></tr></thead>
      <tbody>#{body}</tbody>
    </table>
    """
  end

  defp jobs_simple_table([], _), do: ~s(<p class="empty">None.</p>)

  defp jobs_simple_table(jobs, opts) do
    include_schedule? = Keyword.get(opts, :include_schedule, true)

    headers =
      if include_schedule? do
        "<tr><th>Client</th><th>Status</th><th>Scheduled</th><th>Work</th></tr>"
      else
        "<tr><th>Client</th><th>Status</th><th>Created</th><th>Work</th></tr>"
      end

    body =
      Enum.map_join(jobs, "\n", fn job ->
        third =
          if include_schedule? do
            format_schedule(job.scheduled_on, job.scheduled_time)
          else
            format_dt(job.inserted_at)
          end

        """
        <tr>
          <td>#{esc(job.client_name || "—")}</td>
          <td>#{esc(status_label(job.status))}</td>
          <td>#{esc(third)}</td>
          <td>#{esc(truncate(job.work_description, 80))}</td>
        </tr>
        """
      end)

    """
    <table>
      <thead>#{headers}</thead>
      <tbody>#{body}</tbody>
    </table>
    """
  end

  defp customers_table([]), do: ~s(<p class="empty">No customers.</p>)

  defp customers_table(rows) do
    Enum.map_join(rows, "\n", fn c ->
      """
      <article class="customer">
        <h3>#{esc(c.client_name)}</h3>
        <dl>
          <dt>Phone</dt><dd>#{esc(dash(c.phone))}</dd>
          <dt>Email</dt><dd>#{esc(dash(c.client_email))}</dd>
          <dt>Service address</dt><dd>#{esc(dash(c.address))}</dd>
          <dt>Billing</dt><dd>#{esc(dash(c.billing_address))}</dd>
          <dt>Jobs</dt><dd>#{c.job_count}</dd>
          <dt>Notes</dt><dd>#{esc(dash(c.notes))}</dd>
        </dl>
      </article>
      """
    end)
  end

  defp format_minutes(nil), do: "—"

  defp format_minutes(mins) when is_integer(mins) do
    h = div(mins, 60)
    m = rem(mins, 60)

    cond do
      h == 0 -> "#{m}m"
      m == 0 -> "#{h}h"
      true -> "#{h}h #{m}m"
    end
  end

  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")
  defp format_date(_), do: "—"

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")
  defp format_dt(_), do: "—"

  defp format_naive(nil), do: nil
  defp format_naive(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d %H:%M")

  defp format_schedule(nil, _), do: "—"

  defp format_schedule(%Date{} = d, nil), do: format_date(d)

  defp format_schedule(%Date{} = d, %Time{} = t) do
    "#{format_date(d)} #{Calendar.strftime(t, "%H:%M")}"
  end

  defp status_label(nil), do: "—"
  defp status_label(:lead), do: "Lead"
  defp status_label(:pending), do: "Pending"
  defp status_label(:in_progress), do: "In progress"
  defp status_label(:done), do: "Done"
  defp status_label(other), do: other |> to_string() |> String.replace("_", " ")

  defp kind_label(nil), do: "—"
  defp kind_label(:live_punch), do: "Live"
  defp kind_label(:sms_punch), do: "SMS"
  defp kind_label(:manual_entry), do: "Manual"
  defp kind_label(:sms_shift), do: "SMS shift"
  defp kind_label(other), do: to_string(other)

  defp truncate(nil, _), do: "—"

  defp truncate(text, max) when is_binary(text) do
    text = String.trim(text)

    if String.length(text) <= max do
      text
    else
      String.slice(text, 0, max - 1) <> "…"
    end
  end

  defp dash(nil), do: "—"
  defp dash(""), do: "—"
  defp dash(v), do: v

  defp esc(nil), do: ""

  defp esc(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
