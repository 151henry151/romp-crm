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
              "grid grid-cols-[auto_minmax(0,1fr)_auto_auto] gap-x-2 gap-y-0 py-1 first:pt-0 items-start min-h-0",
              wi.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0 flex items-center pt-0.5">
                <%= if @can_edit_jobs do %>
                  <input
                    type="checkbox"
                    checked={wi.completed}
                    class="checkbox checkbox-xs border-base-300 scale-90 origin-left"
                    phx-click="toggle_work_item_completed"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    aria-label={"Mark work item complete: #{wi.title}"}
                  />
                <% else %>
                  <input type="checkbox" checked={wi.completed} disabled class="checkbox checkbox-xs opacity-50 scale-90" />
                <% end %>
              </div>
              <div class="min-w-0 py-0.5">
                <p class="whitespace-pre-wrap break-words text-sm text-base-content leading-tight">
                  {wi.title}
                </p>
              </div>
              <div class="shrink-0 flex items-center justify-end gap-1.5 pl-1 pt-0.5">
                <%= if @can_edit_jobs do %>
                  <%= if wi.scheduled_on do %>
                    <span class="text-[11px] tabular-nums text-base-content/60 whitespace-nowrap max-sm:max-w-[4.5rem] max-sm:truncate" title={Date.to_iso8601(wi.scheduled_on)}>
                      {Date.to_iso8601(wi.scheduled_on)}
                    </span>
                  <% end %>
                  <label
                    class="relative inline-flex h-6 w-6 shrink-0 cursor-pointer items-center justify-center rounded border border-base-content/15 bg-base-300/15 text-base-content/45 hover:border-base-content/25 hover:bg-base-300/30 hover:text-base-content/70"
                    title="Schedule date"
                  >
                    <input
                      type="date"
                      id={"work-item-date-#{wi.id}"}
                      name={"work_item_#{wi.id}_scheduled_on"}
                      value={wi.scheduled_on && Date.to_iso8601(wi.scheduled_on)}
                      class="absolute inset-0 z-10 h-full w-full cursor-pointer opacity-0"
                      phx-change="work_item_scheduled_on"
                      phx-value-job_id={@job.id}
                      phx-value-work_item_id={wi.id}
                      aria-label={"Set date for: #{wi.title}"}
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
                <% else %>
                  <%= if wi.scheduled_on do %>
                    <span class="text-[11px] tabular-nums text-base-content/55 whitespace-nowrap">
                      {Date.to_iso8601(wi.scheduled_on)}
                    </span>
                  <% end %>
                <% end %>
              </div>
              <div class="shrink-0 flex justify-end pt-0.5">
                <%= if @can_edit_jobs do %>
                  <button
                    type="button"
                    phx-click="delete_work_item"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    data-confirm="Remove this work item?"
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
              "grid grid-cols-[auto_auto_minmax(0,1fr)_auto_auto] gap-x-2 gap-y-0 py-1 first:pt-0 items-start min-h-0",
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
              <div class="w-14 sm:w-16 shrink-0 pt-0.5">
                <%= if @can_edit_jobs do %>
                  <input
                    type="number"
                    step="any"
                    min="0.0001"
                    name={"material_#{m.id}_quantity"}
                    value={format_qty_value(m.quantity)}
                    class="input input-bordered input-xs h-7 min-h-0 w-full px-1 py-0 text-xs leading-none"
                    phx-change="material_quantity"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                  />
                <% else %>
                  <span class="text-[11px] tabular-nums">{format_qty_value(m.quantity)}</span>
                <% end %>
              </div>
              <div class="min-w-0 py-0.5">
                <p class="break-words leading-tight text-sm">
                  <span class="text-base-content/55">{m.scope_label}:</span>
                  <span class="text-base-content">{m.description}</span>
                </p>
              </div>
              <div class="w-[5.25rem] sm:w-24 shrink-0 pt-0.5">
                <%= if @can_edit_jobs do %>
                  <div class="relative w-full">
                    <span class="pointer-events-none absolute left-1.5 top-1/2 -translate-y-1/2 text-[10px] text-base-content/45">
                      $
                    </span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      name={"material_#{m.id}_unit_price"}
                      value={format_price_input(m.unit_price)}
                      class="input input-bordered input-xs h-7 min-h-0 w-full py-0 pl-4 pr-0.5 text-xs leading-none"
                      phx-change="material_unit_price"
                      phx-value-job_id={@job.id}
                      phx-value-material_id={m.id}
                    />
                  </div>
                <% else %>
                  <span class="text-[11px] text-base-content/80 tabular-nums">
                    <%= if m.unit_price do %>
                      ${format_price_input(m.unit_price)}
                    <% else %>
                      —
                    <% end %>
                  </span>
                <% end %>
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

  defp format_price_input(nil), do: ""
  defp format_price_input(n) when is_float(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp format_price_input(n) when is_integer(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp format_price_input(_), do: ""
end
