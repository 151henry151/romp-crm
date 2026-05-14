defmodule RompCrmWeb.JobExpandLists do
  @moduledoc false
  use Phoenix.Component

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :wrapper_class, :string, default: "pt-1"

  def job_work_items_section(assigns) do
    ~H"""
    <%= if @job.work_items != [] && @job.work_items do %>
      <div class={@wrapper_class}>
        <p class="font-medium text-base-content/90 mb-1.5 text-sm">Work items:</p>
        <div class="divide-y divide-dotted divide-base-content/15">
          <%= for wi <- @job.work_items do %>
            <div class={[
              "flex flex-nowrap items-center gap-2 py-1 first:pt-0 min-h-0 min-w-0",
              wi.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0 flex items-center leading-none">
                <%= if @can_edit_jobs do %>
                  <input
                    type="checkbox"
                    checked={wi.completed}
                    class="checkbox checkbox-sm border-base-300"
                    phx-click="toggle_work_item_completed"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    aria-label={"Mark work item complete: #{wi.title}"}
                  />
                <% else %>
                  <input
                    type="checkbox"
                    checked={wi.completed}
                    disabled
                    class="checkbox checkbox-sm opacity-50"
                  />
                <% end %>
              </div>
              <div class="flex min-w-0 flex-1 flex-nowrap items-center gap-x-1.5 overflow-hidden">
                <%= if @can_edit_jobs do %>
                  <input
                    type="text"
                    name={"work_item_#{wi.id}_title"}
                    value={wi.title}
                    phx-change="work_item_title"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    phx-debounce="400"
                    class="input input-bordered input-xs min-w-0 flex-1 text-sm text-base-content"
                    title={wi.title}
                  />
                <% else %>
                  <span class="min-w-0 flex-1 truncate text-sm text-base-content" title={wi.title}>
                    {wi.title}
                  </span>
                <% end %>
                <%= if wi.scheduled_on do %>
                  <span class="shrink-0 text-[11px] tabular-nums text-base-content/65 whitespace-nowrap">
                    {Date.to_iso8601(wi.scheduled_on)}
                  </span>
                <% end %>
                <%= if @can_edit_jobs do %>
                  <label
                    class="relative inline-flex h-6 w-6 shrink-0 cursor-pointer items-center justify-center rounded border border-base-content/20 bg-base-300/20 text-base-content/50 hover:border-base-content/35 hover:bg-base-300/35 hover:text-base-content/75"
                    title="Set date"
                  >
                    <input
                      type="date"
                      name={"work_item_#{wi.id}_scheduled_on"}
                      value={wi.scheduled_on && Date.to_iso8601(wi.scheduled_on)}
                      class="absolute inset-0 z-10 h-full w-full cursor-pointer opacity-0"
                      phx-change="work_item_scheduled_on"
                      phx-value-job_id={@job.id}
                      phx-value-work_item_id={wi.id}
                      aria-label={"Scheduled date for: #{wi.title}"}
                    />
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 16 16"
                      fill="currentColor"
                      class="pointer-events-none h-3.5 w-3.5"
                      aria-hidden="true"
                    >
                      <path d="M3.5 0a.5.5 0 0 1 .5.5V1h8V.5a.5.5 0 0 1 1 0V1h1a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2h1V.5a.5.5 0 0 1 .5-.5zM1 4v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V4H1z" />
                    </svg>
                  </label>
                <% end %>
              </div>
              <div class="shrink-0 flex items-center leading-none">
                <%= if @can_edit_jobs do %>
                  <button
                    type="button"
                    phx-click="delete_work_item"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    data-confirm="Remove this work item?"
                    class="btn btn-square btn-ghost btn-xs h-6 w-6 min-h-0 shrink-0 border border-red-500/35 p-0 text-sm font-semibold leading-none text-red-500 hover:bg-red-500/15 hover:text-red-400"
                    aria-label="Remove work item"
                  >
                    ×
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :wrapper_class, :string, default: "pt-1"

  def job_materials_section(assigns) do
    mc = RompCrm.Jobs.materials_combined(assigns.job)
    assigns = assign(assigns, :mc, mc)

    ~H"""
    <%= if @mc != [] do %>
      <div class={@wrapper_class}>
        <p class="font-medium text-base-content/90 mb-1.5 text-sm">Materials</p>
        <div class="divide-y divide-dotted divide-base-content/15 text-sm">
          <%= for m <- @mc do %>
            <div class={[
              "flex flex-nowrap items-center gap-1.5 py-1 first:pt-0 min-w-0",
              m.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0 flex items-center">
                <%= if @can_edit_jobs do %>
                  <input
                    type="checkbox"
                    checked={m.completed}
                    class="checkbox checkbox-xs border-base-300"
                    phx-click="toggle_material_completed"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                    aria-label={"Mark material complete: #{m.description}"}
                  />
                <% else %>
                  <input
                    type="checkbox"
                    checked={m.completed}
                    disabled
                    class="checkbox checkbox-xs opacity-50"
                  />
                <% end %>
              </div>
              <span class="shrink-0 text-xs font-medium text-base-content/70">Qty:</span>
              <%= if @can_edit_jobs do %>
                <input
                  type="number"
                  step="any"
                  min="0.0001"
                  name={"material_#{m.id}_quantity"}
                  value={format_qty_value(m.quantity)}
                  size={material_qty_input_size(m.quantity)}
                  phx-change="material_quantity"
                  phx-value-job_id={@job.id}
                  phx-value-material_id={m.id}
                  class="input input-bordered input-xs box-border h-6 w-9 max-w-[2.75rem] shrink-0 px-0.5 py-0 text-center text-xs leading-none tabular-nums sm:max-w-[4rem] sm:[field-sizing:content]"
                />
              <% else %>
                <span class="shrink-0 text-[11px] tabular-nums text-base-content">
                  {format_qty_value(m.quantity)}
                </span>
              <% end %>
              <div class="flex min-w-0 flex-1 items-center gap-0.5 leading-tight">
                <%= if m.scope_label != "Job" do %>
                  <span class="shrink-0 text-base-content/55 text-xs">{m.scope_label}:</span>
                <% end %>
                <%= if @can_edit_jobs do %>
                  <input
                    type="text"
                    name={"material_#{m.id}_description"}
                    value={m.description}
                    phx-change="material_description"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                    phx-debounce="400"
                    class="input input-bordered input-xs min-w-0 flex-1 text-sm text-base-content"
                    title={material_line_title(m)}
                  />
                <% else %>
                  <p class="min-w-0 flex-1 truncate text-sm" title={material_line_title(m)}>
                    <span class="text-base-content">{m.description}</span>
                  </p>
                <% end %>
              </div>
              <%= if @can_edit_jobs do %>
                <button
                  type="button"
                  phx-click="delete_material"
                  phx-value-job_id={@job.id}
                  phx-value-material_id={m.id}
                  data-confirm="Remove this material line?"
                  class="btn btn-square btn-ghost btn-xs h-6 w-6 min-h-0 shrink-0 border border-red-500/35 p-0 text-sm font-semibold leading-none text-red-500 hover:bg-red-500/15 hover:text-red-400"
                  aria-label="Remove material"
                >
                  ×
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp material_line_title(m) do
    if m.scope_label != "Job" do
      "#{m.scope_label}: #{m.description}"
    else
      m.description
    end
  end

  defp format_qty_value(n) when is_float(n) do
    t = trunc(n)
    if n == t * 1.0, do: Integer.to_string(t), else: Float.to_string(n)
  end

  defp format_qty_value(n) when is_integer(n), do: Integer.to_string(n)
  defp format_qty_value(_), do: "1"

  defp material_qty_input_size(qty) do
    n = qty |> format_qty_value() |> String.length()
    min(max(n + 1, 2), 8)
  end
end
