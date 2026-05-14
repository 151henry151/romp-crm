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
              "grid grid-cols-[auto_minmax(0,1fr)_auto_auto] items-center gap-x-2 py-0.5 first:pt-0 min-h-0",
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
                  <input type="checkbox" checked={wi.completed} disabled class="checkbox checkbox-sm opacity-50" />
                <% end %>
              </div>
              <div class="min-w-0 overflow-hidden leading-none">
                <p class="truncate text-sm text-base-content" title={wi.title}>
                  {wi.title}
                </p>
              </div>
              <div class="shrink-0 flex items-center justify-end">
                <%= if @can_edit_jobs do %>
                  <input
                    type="date"
                    name={"work_item_#{wi.id}_scheduled_on"}
                    value={wi.scheduled_on && Date.to_iso8601(wi.scheduled_on)}
                    class="input input-bordered input-xs h-7 w-[9.25rem] max-w-[36vw] shrink-0 px-2 py-0 text-xs leading-tight"
                    phx-change="work_item_scheduled_on"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    aria-label={"Scheduled date for: #{wi.title}"}
                  />
                <% else %>
                  <span class="text-xs text-base-content/70 tabular-nums whitespace-nowrap h-7 inline-flex items-center">
                    <%= if wi.scheduled_on do %>
                      {Date.to_iso8601(wi.scheduled_on)}
                    <% else %>
                      —
                    <% end %>
                  </span>
                <% end %>
              </div>
              <div class="shrink-0 flex items-center justify-end leading-none">
                <%= if @can_edit_jobs do %>
                  <button
                    type="button"
                    phx-click="delete_work_item"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    data-confirm="Remove this work item?"
                    class="text-xs font-medium text-red-500/90 hover:text-red-400 whitespace-nowrap"
                  >
                    Remove
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
              "grid grid-cols-[auto_auto_minmax(0,1fr)_auto] gap-x-2 gap-y-0 py-1 first:pt-0 items-start min-h-0",
              m.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0 flex items-center pt-0.5">
                <%= if @can_edit_jobs do %>
                  <input
                    type="checkbox"
                    checked={m.completed}
                    class="checkbox checkbox-xs border-base-300 scale-90 origin-left"
                    phx-click="toggle_material_completed"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                    aria-label={"Mark material complete: #{m.description}"}
                  />
                <% else %>
                  <input type="checkbox" checked={m.completed} disabled class="checkbox checkbox-xs opacity-50 scale-90" />
                <% end %>
              </div>
              <div class="flex shrink-0 items-center gap-1 pt-0.5">
                <span class="text-xs font-medium text-base-content/70 whitespace-nowrap">Qty:</span>
                <%= if @can_edit_jobs do %>
                  <input
                    type="number"
                    step="any"
                    min="0.0001"
                    name={"material_#{m.id}_quantity"}
                    value={format_qty_value(m.quantity)}
                    size={material_qty_input_size(m.quantity)}
                    class="input input-bordered input-xs box-border h-7 min-w-0 max-w-[12ch] px-1 py-0 text-xs leading-none tabular-nums [field-sizing:content]"
                    phx-change="material_quantity"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                  />
                <% else %>
                  <span class="text-[11px] tabular-nums text-base-content">{format_qty_value(m.quantity)}</span>
                <% end %>
              </div>
              <div class="min-w-0 py-0.5">
                <p class="break-words leading-tight text-sm">
                  <span class="text-base-content/55">{m.scope_label}:</span>
                  <span class="text-base-content">{m.description}</span>
                </p>
              </div>
              <div class="shrink-0 flex justify-end pt-0.5">
                <%= if @can_edit_jobs do %>
                  <button
                    type="button"
                    phx-click="delete_material"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                    data-confirm="Remove this material line?"
                    class="text-[11px] leading-none text-red-500/90 hover:text-red-400 font-medium"
                  >
                    Remove
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

  defp format_qty_value(n) when is_float(n) do
    t = trunc(n)
    if n == t * 1.0, do: Integer.to_string(t), else: Float.to_string(n)
  end

  defp format_qty_value(n) when is_integer(n), do: Integer.to_string(n)
  defp format_qty_value(_), do: "1"

  # HTML `size` (character columns) + `field-sizing: content` so the box stays narrow for 1–9
  # and grows when the saved value has more digits or decimals (re-renders after `phx-change`).
  defp material_qty_input_size(qty) do
    n = qty |> format_qty_value() |> String.length()
    min(max(n + 2, 2), 14)
  end
end
