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
        <p class="font-medium text-base-content/90 mb-2">Work items</p>
        <div class="space-y-0 divide-y divide-dotted divide-base-300/60">
          <%= for wi <- @job.work_items do %>
            <div class={[
              "grid grid-cols-[auto_auto_1fr_auto] gap-x-2 gap-y-1 py-2 first:pt-0 items-start",
              wi.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="pt-0.5 shrink-0">
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
              <div class="shrink-0 w-[9.5rem] max-w-[42vw]">
                <%= if @can_edit_jobs do %>
                  <input
                    type="date"
                    name={"work_item_#{wi.id}_scheduled_on"}
                    value={wi.scheduled_on && Date.to_iso8601(wi.scheduled_on)}
                    class="input input-bordered input-xs w-full text-xs"
                    phx-change="work_item_scheduled_on"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                  />
                <% else %>
                  <span class="text-xs text-base-content/70">
                    <%= if wi.scheduled_on do %>
                      {Date.to_iso8601(wi.scheduled_on)}
                    <% else %>
                      —
                    <% end %>
                  </span>
                <% end %>
              </div>
              <div class="min-w-0">
                <p class="whitespace-pre-wrap break-words text-sm text-base-content leading-snug">
                  {wi.title}
                </p>
              </div>
              <div class="shrink-0 flex justify-end">
                <%= if @can_edit_jobs do %>
                  <button
                    type="button"
                    phx-click="delete_work_item"
                    phx-value-job_id={@job.id}
                    phx-value-work_item_id={wi.id}
                    data-confirm="Remove this work item?"
                    class="text-xs text-red-500 hover:text-red-400 font-medium"
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
        <p class="font-medium text-base-content/90 mb-2">Materials</p>
        <div class="space-y-0 divide-y divide-dotted divide-base-300/60 text-sm">
          <%= for m <- @mc do %>
            <div class={[
              "grid grid-cols-[auto_auto_minmax(0,1fr)_auto_auto] gap-x-2 gap-y-1 py-2 first:pt-0 items-center",
              m.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0">
                <%= if @can_edit_jobs do %>
                  <input
                    type="checkbox"
                    checked={m.completed}
                    class="checkbox checkbox-sm border-base-300"
                    phx-click="toggle_material_completed"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                    aria-label={"Mark material complete: #{m.description}"}
                  />
                <% else %>
                  <input type="checkbox" checked={m.completed} disabled class="checkbox checkbox-sm opacity-50" />
                <% end %>
              </div>
              <div class="w-16 sm:w-20 shrink-0">
                <%= if @can_edit_jobs do %>
                  <input
                    type="number"
                    step="any"
                    min="0.0001"
                    name={"material_#{m.id}_quantity"}
                    value={format_qty_value(m.quantity)}
                    class="input input-bordered input-xs w-full text-xs px-1"
                    phx-change="material_quantity"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                  />
                <% else %>
                  <span class="text-xs tabular-nums">{format_qty_value(m.quantity)}</span>
                <% end %>
              </div>
              <div class="min-w-0">
                <p class="break-words">
                  <span class="text-base-content/60">{m.scope_label}:</span>
                  <span class="text-base-content">{m.description}</span>
                </p>
              </div>
              <div class="w-24 sm:w-28 shrink-0">
                <%= if @can_edit_jobs do %>
                  <div class="relative w-full">
                    <span class="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-[10px] text-base-content/50">
                      $
                    </span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      name={"material_#{m.id}_unit_price"}
                      value={format_price_input(m.unit_price)}
                      class="input input-bordered input-xs w-full text-xs pl-5 pr-1"
                      phx-change="material_unit_price"
                      phx-value-job_id={@job.id}
                      phx-value-material_id={m.id}
                    />
                  </div>
                <% else %>
                  <span class="text-xs text-base-content/80 tabular-nums">
                    <%= if m.unit_price do %>
                      ${format_price_input(m.unit_price)}
                    <% else %>
                      —
                    <% end %>
                  </span>
                <% end %>
              </div>
              <div class="shrink-0 flex justify-end">
                <%= if @can_edit_jobs do %>
                  <button
                    type="button"
                    phx-click="delete_material"
                    phx-value-job_id={@job.id}
                    phx-value-material_id={m.id}
                    data-confirm="Remove this material line?"
                    class="text-xs text-red-500 hover:text-red-400 font-medium"
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
