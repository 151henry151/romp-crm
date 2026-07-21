defmodule RompCrm.JobPrint.Html do
  @moduledoc false

  alias RompCrm.TimeTracking.TimeEntry

  @doc "Full HTML document for a single-job PDF."
  def job_document(report, _generated_at) do
    job = report.job
    title = headline(job)

    body =
      [
        masthead(report.business_name, title, job.id),
        summary_block(job, report.total_minutes),
        optional_section("Contact & schedule", details_dl(job, report)),
        optional_section("Work description", prose(job.work_description)),
        optional_section("Customer comments", prose(job.customer_comments)),
        optional_section("Notes", prose(job.notes)),
        optional_section("Next action", prose(job.next_action)),
        optional_section("Work items", work_items_table(report.work_items)),
        optional_section("Materials", materials_table(report.materials)),
        optional_section("Hours logged", hours_table(report.time_entries)),
        optional_section("Photos", photos_block(report.photos))
      ]
      |> Enum.reject(&(&1 in ["", nil]))
      |> Enum.join("\n")

    wrap(title, body)
  end

  defp headline(%{client_name: name}) when is_binary(name) and name != "", do: name
  defp headline(_), do: "Job details"

  defp masthead(business_name, title, job_id) do
    """
    <header class="masthead">
      <p class="eyebrow">#{esc(business_name)}</p>
      <h1>#{esc(title)}</h1>
      <p class="sub">Job ##{job_id}</p>
    </header>
    """
  end

  defp summary_block(job, total_minutes) do
    stats =
      [
        {"Status", status_label(job.status)},
        {"Priority", priority_label(job.priority)},
        if(is_integer(total_minutes) and total_minutes > 0,
          do: {"Hours logged", format_minutes(total_minutes)},
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {_lbl, val} -> present?(val) end)

    if stats == [] do
      ""
    else
      inner =
        Enum.map_join(stats, "\n", fn {lbl, val} ->
          ~s(<div class="stat"><span class="num">#{esc(val)}</span><span class="lbl">#{esc(lbl)}</span></div>)
        end)

      """
      <section class="summary">
      #{inner}
      </section>
      """
    end
  end

  defp details_dl(job, report) do
    rows =
      [
        {"Client", job.client_name},
        {"Phone", job.phone},
        {"Email", job.client_email},
        {"Service address", blankable_address(report.service_address)},
        {"Billing address", report.billing_address},
        {"Scheduled", schedule_value(job.scheduled_on, job.scheduled_time)},
        {"Referred by", job.referred_by},
        {"Created", format_dt(job.inserted_at)},
        {"Updated", format_dt(job.updated_at)}
      ]
      |> Enum.filter(fn {_label, value} -> present?(value) end)

    if rows == [] do
      nil
    else
      body =
        Enum.map_join(rows, "\n", fn {label, value} ->
          "<div class=\"row\"><dt>#{esc(label)}</dt><dd>#{esc(value)}</dd></div>"
        end)

      """
      <dl class="details">
      #{body}
      </dl>
      """
    end
  end

  defp blankable_address(nil), do: nil
  defp blankable_address(""), do: nil
  defp blankable_address("—"), do: nil
  defp blankable_address(v), do: v

  defp schedule_value(nil, _), do: nil
  defp schedule_value(%Date{} = d, nil), do: format_date(d)

  defp schedule_value(%Date{} = d, %Time{} = t) do
    "#{format_date(d)} #{Calendar.strftime(t, "%H:%M")}"
  end

  defp work_items_table([]), do: nil

  defp work_items_table(items) do
    body =
      Enum.map_join(items, "\n", fn wi ->
        """
        <tr>
          <td>#{esc(wi.title)}</td>
          <td>#{esc(schedule_value(wi.scheduled_on, wi.scheduled_time) || "")}</td>
          <td>#{esc(if(wi.completed, do: "Done", else: "Open"))}</td>
        </tr>
        """
      end)

    """
    <table>
      <thead><tr><th>Task</th><th>Scheduled</th><th>Status</th></tr></thead>
      <tbody>#{body}</tbody>
    </table>
    """
  end

  defp materials_table([]), do: nil

  defp materials_table(rows) do
    show_price? =
      Enum.any?(rows, fn m -> present?(Map.get(m, :unit_price) || Map.get(m, "unit_price")) end)

    headers =
      if show_price? do
        "<tr><th>Material</th><th>Qty</th><th>Unit price</th><th>On</th><th>Status</th></tr>"
      else
        "<tr><th>Material</th><th>Qty</th><th>On</th><th>Status</th></tr>"
      end

    body =
      Enum.map_join(rows, "\n", fn m ->
        qty = format_qty(Map.get(m, :quantity) || Map.get(m, "quantity"))
        desc = Map.get(m, :description) || Map.get(m, "description")
        scope = Map.get(m, :scope_label) || Map.get(m, :scope) || "Job"
        done? = Map.get(m, :completed) || Map.get(m, "completed")
        price = format_money(Map.get(m, :unit_price) || Map.get(m, "unit_price"))
        price_cell = if show_price?, do: "<td>#{esc(price || "")}</td>", else: ""

        """
        <tr>
          <td>#{esc(desc)}</td>
          <td>#{esc(qty || "")}</td>
          #{price_cell}
          <td>#{esc(to_string(scope))}</td>
          <td>#{esc(if(done?, do: "Purchased", else: "Needed"))}</td>
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

  defp hours_table([]), do: nil

  defp hours_table(entries) do
    show_notes? = Enum.any?(entries, &present?(&1.notes))

    headers =
      if show_notes? do
        "<tr><th>Started</th><th>Ended</th><th>Duration</th><th>Notes</th></tr>"
      else
        "<tr><th>Started</th><th>Ended</th><th>Duration</th></tr>"
      end

    body =
      Enum.map_join(entries, "\n", fn te ->
        notes_cell = if show_notes?, do: "<td>#{esc(te.notes || "")}</td>", else: ""

        """
        <tr>
          <td>#{esc(format_naive(te.started_at))}</td>
          <td>#{esc(format_naive(te.ended_at) || "Open")}</td>
          <td>#{esc(format_minutes(TimeEntry.duration_minutes(te)) || "")}</td>
          #{notes_cell}
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

  defp photos_block([]), do: nil

  defp photos_block(photos) do
    Enum.map_join(photos, "\n", fn photo ->
      """
      <figure class="photo">
        <img src="#{photo.data_uri}" alt="Job photo #{photo.index}" />
        <figcaption>Photo #{photo.index}</figcaption>
      </figure>
      """
    end)
  end

  defp prose(value) do
    if present?(value) do
      paragraphs =
        value
        |> to_string()
        |> String.trim()
        |> String.split(~r/\n{2,}/, trim: true)
        |> Enum.map_join("\n", fn para ->
          lines =
            para
            |> String.split("\n")
            |> Enum.map_join("<br />", &esc/1)

          "<p>#{lines}</p>"
        end)

      if paragraphs == "", do: nil, else: paragraphs
    else
      nil
    end
  end

  defp optional_section(_title, nil), do: ""
  defp optional_section(_title, ""), do: ""

  defp optional_section(title, inner) when is_binary(inner) do
    "<section><h2>#{esc(title)}</h2>#{inner}</section>"
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
    .eyebrow {
      margin: 0 0 0.2rem;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 9pt;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: #64748b;
    }
    h1 {
      margin: 0 0 0.2rem;
      font-size: 18pt;
      font-weight: 700;
      letter-spacing: -0.02em;
      color: #0b1c2c;
    }
    .sub {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 9pt;
      color: #64748b;
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
      font-size: 14pt;
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
    .details {
      margin: 0.35rem 0 0.5rem;
      display: grid;
      gap: 0.35rem 0;
    }
    .details .row {
      display: grid;
      grid-template-columns: 8rem 1fr;
      gap: 0.35rem 0.75rem;
    }
    .details dt {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 8pt;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: #64748b;
    }
    .details dd { margin: 0; color: #1a2332; }
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
    p { margin: 0.35rem 0 0.75rem; white-space: pre-wrap; }
    .photo {
      break-inside: avoid;
      margin: 0.6rem 0 1rem;
      padding: 0;
    }
    .photo img {
      display: block;
      max-width: 100%;
      max-height: 4.8in;
      height: auto;
      border: 0.75pt solid #cbd5e1;
    }
    .photo figcaption {
      margin-top: 0.25rem;
      font-family: "Avenir Next", "Segoe UI", system-ui, sans-serif;
      font-size: 8pt;
      color: #64748b;
    }
    """
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?("—"), do: false

  defp present?(s) when is_binary(s), do: String.trim(s) != ""

  defp present?(n) when is_number(n), do: true
  defp present?(%Date{}), do: true
  defp present?(%DateTime{}), do: true
  defp present?(%NaiveDateTime{}), do: true
  defp present?(%Time{}), do: true
  defp present?(_), do: false

  defp format_minutes(nil), do: nil

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
  defp format_date(_), do: nil

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")
  defp format_dt(_), do: nil

  defp format_naive(nil), do: nil
  defp format_naive(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y %H:%M")

  defp format_qty(nil), do: nil

  defp format_qty(n) when is_float(n),
    do: :erlang.float_to_binary(n, decimals: 2) |> String.trim_trailing("0") |> String.trim_trailing(".")

  defp format_qty(n) when is_integer(n), do: Integer.to_string(n)
  defp format_qty(n), do: to_string(n)

  defp format_money(nil), do: nil
  defp format_money(n) when is_number(n), do: "$#{:erlang.float_to_binary(n * 1.0, decimals: 2)}"
  defp format_money(_), do: nil

  defp status_label(nil), do: nil
  defp status_label(:lead), do: "Lead"
  defp status_label(:pending), do: "Pending"
  defp status_label(:in_progress), do: "In progress"
  defp status_label(:done), do: "Done"
  defp status_label(other), do: other |> to_string() |> String.replace("_", " ")

  defp priority_label(:high), do: "High"
  defp priority_label(:normal), do: "Normal"
  defp priority_label(nil), do: nil
  defp priority_label(other), do: to_string(other)

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
