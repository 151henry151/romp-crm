defmodule RompCrmWeb.JobExpandLists do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1]

  alias RompCrmWeb.JobExpandEditKeys, as: EK

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :edit_keys, :any, required: true
  attr :wrapper_class, :string, default: "pt-1"

  def job_work_items_section(assigns) do
    ~H"""
    <%= if @job.work_items != [] && @job.work_items do %>
      <div class={@wrapper_class}>
        <p class="font-medium text-base-content/90 mb-1.5 text-sm">Work items:</p>
        <div class="divide-y divide-dotted divide-base-content/15">
          <%= for wi <- @job.work_items do %>
            <div class={[
              "flex flex-wrap items-start gap-2 py-1 first:pt-0 min-h-0 min-w-0",
              wi.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0 flex items-start pt-0.5 leading-none">
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
              <div class="flex min-w-0 flex-1 flex-wrap items-start gap-x-1.5 gap-y-1">
                <%= if @can_edit_jobs do %>
                  <%= if editing?(@edit_keys, EK.wi_title(wi.id)) do %>
                    <form
                      phx-submit="job_expand_commit_wi_title"
                      class="flex min-w-0 flex-1 flex-wrap items-start gap-1"
                    >
                      <input type="hidden" name="job_id" value={@job.id} />
                      <input type="hidden" name="work_item_id" value={wi.id} />
                      <input
                        type="text"
                        name="value"
                        value={wi.title}
                        class="input input-bordered input-xs min-w-0 flex-1 text-sm text-base-content"
                      />
                      <button
                        type="submit"
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                        aria-label="Save work item title"
                      >
                        <.icon name="hero-check" class="size-4" />
                      </button>
                      <button
                        type="button"
                        phx-click="job_expand_edit_cancel"
                        phx-value-key={EK.wi_title(wi.id)}
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-base-content/50 hover:bg-base-300/40"
                        aria-label="Cancel"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </form>
                  <% else %>
                    <div class="flex min-w-0 flex-1 flex-wrap items-start gap-1">
                      <span class="min-w-0 flex-1 text-sm text-base-content break-words">
                        {wi.title}
                      </span>
                      <button
                        type="button"
                        phx-click="job_expand_edit_start"
                        phx-value-key={EK.wi_title(wi.id)}
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                        aria-label="Edit work item title"
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                <% else %>
                  <span class="min-w-0 flex-1 text-sm text-base-content break-words">
                    {wi.title}
                  </span>
                <% end %>
                <%= if @can_edit_jobs do %>
                  <%= if editing?(@edit_keys, EK.wi_scheduled(wi.id)) do %>
                    <form
                      phx-submit="job_expand_commit_wi_scheduled"
                      class="flex shrink-0 flex-wrap items-start gap-0.5"
                    >
                      <input type="hidden" name="job_id" value={@job.id} />
                      <input type="hidden" name="work_item_id" value={wi.id} />
                      <input
                        type="date"
                        name="value"
                        value={wi.scheduled_on && Date.to_iso8601(wi.scheduled_on)}
                        class="input input-bordered input-xs h-7 w-[10.5rem] shrink-0 px-1 text-[11px] tabular-nums"
                      />
                      <button
                        type="submit"
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                        aria-label="Save scheduled date"
                      >
                        <.icon name="hero-check" class="size-4" />
                      </button>
                      <button
                        type="button"
                        phx-click="job_expand_edit_cancel"
                        phx-value-key={EK.wi_scheduled(wi.id)}
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-base-content/50 hover:bg-base-300/40"
                        aria-label="Cancel date edit"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </form>
                  <% else %>
                    <div class="flex shrink-0 flex-wrap items-start gap-0.5">
                      <span class="text-[11px] tabular-nums text-base-content/65 whitespace-nowrap">
                        <%= if wi.scheduled_on do %>
                          {Date.to_iso8601(wi.scheduled_on)}
                        <% else %>
                          —
                        <% end %>
                      </span>
                      <button
                        type="button"
                        phx-click="job_expand_edit_start"
                        phx-value-key={EK.wi_scheduled(wi.id)}
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                        aria-label="Edit scheduled date"
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                <% else %>
                  <%= if wi.scheduled_on do %>
                    <span class="shrink-0 text-[11px] tabular-nums text-base-content/65 whitespace-nowrap">
                      {Date.to_iso8601(wi.scheduled_on)}
                    </span>
                  <% end %>
                <% end %>
              </div>
              <div class="shrink-0 flex items-start pt-0.5 leading-none">
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
  attr :edit_keys, :any, required: true
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
              "flex flex-wrap items-start gap-1.5 py-1 first:pt-0 min-w-0",
              m.completed && "opacity-55 text-base-content/75"
            ]}>
              <div class="shrink-0 flex items-start pt-0.5">
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
                <%= if editing?(@edit_keys, EK.mat_quantity(m.id)) do %>
                  <form
                    phx-submit="job_expand_commit_material_qty"
                    class="flex shrink-0 items-center gap-0.5"
                  >
                    <input type="hidden" name="job_id" value={@job.id} />
                    <input type="hidden" name="material_id" value={m.id} />
                    <input
                      type="number"
                      step="any"
                      min="0.0001"
                      name="value"
                      value={format_qty_value(m.quantity)}
                      class="input input-bordered input-xs box-border h-6 w-12 max-w-[4rem] shrink-0 px-0.5 py-0 text-center text-xs leading-none tabular-nums"
                    />
                    <button
                      type="submit"
                      class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                      aria-label="Save quantity"
                    >
                      <.icon name="hero-check" class="size-4" />
                    </button>
                    <button
                      type="button"
                      phx-click="job_expand_edit_cancel"
                      phx-value-key={EK.mat_quantity(m.id)}
                      class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-base-content/50 hover:bg-base-300/40"
                      aria-label="Cancel"
                    >
                      <.icon name="hero-x-mark" class="size-3.5" />
                    </button>
                  </form>
                <% else %>
                  <div class="flex shrink-0 items-center gap-0.5">
                    <span class="text-[11px] tabular-nums text-base-content">
                      {format_qty_value(m.quantity)}
                    </span>
                    <button
                      type="button"
                      phx-click="job_expand_edit_start"
                      phx-value-key={EK.mat_quantity(m.id)}
                      class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                      aria-label="Edit quantity"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </button>
                  </div>
                <% end %>
              <% else %>
                <span class="shrink-0 text-[11px] tabular-nums text-base-content">
                  {format_qty_value(m.quantity)}
                </span>
              <% end %>
              <div class="flex min-w-0 flex-1 flex-wrap items-start gap-0.5 leading-tight">
                <%= if m.scope_label != "Job" do %>
                  <span class="shrink-0 text-base-content/55 text-xs">{m.scope_label}:</span>
                <% end %>
                <%= if @can_edit_jobs do %>
                  <%= if editing?(@edit_keys, EK.mat_description(m.id)) do %>
                    <form
                      phx-submit="job_expand_commit_material_desc"
                      class="flex min-w-0 flex-1 flex-wrap items-start gap-1"
                    >
                      <input type="hidden" name="job_id" value={@job.id} />
                      <input type="hidden" name="material_id" value={m.id} />
                      <input
                        type="text"
                        name="value"
                        value={m.description}
                        class="input input-bordered input-xs min-w-0 flex-1 text-sm text-base-content"
                        title={material_line_title(m)}
                      />
                      <button
                        type="submit"
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                        aria-label="Save description"
                      >
                        <.icon name="hero-check" class="size-4" />
                      </button>
                      <button
                        type="button"
                        phx-click="job_expand_edit_cancel"
                        phx-value-key={EK.mat_description(m.id)}
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-base-content/50 hover:bg-base-300/40"
                        aria-label="Cancel"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </form>
                  <% else %>
                    <div class="flex min-w-0 flex-1 flex-wrap items-start gap-1">
                      <p class="min-w-0 flex-1 text-sm break-words">
                        <span class="text-base-content">{m.description}</span>
                      </p>
                      <button
                        type="button"
                        phx-click="job_expand_edit_start"
                        phx-value-key={EK.mat_description(m.id)}
                        class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                        aria-label="Edit material description"
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                <% else %>
                  <p class="min-w-0 flex-1 text-sm break-words">
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
                  class="btn btn-square btn-ghost btn-xs h-6 w-6 min-h-0 shrink-0 self-start border border-red-500/35 p-0 text-sm font-semibold leading-none text-red-500 hover:bg-red-500/15 hover:text-red-400"
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

  defp editing?(keys, key) when is_struct(keys, MapSet), do: MapSet.member?(keys, key)
  defp editing?(_, _), do: false

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
end
