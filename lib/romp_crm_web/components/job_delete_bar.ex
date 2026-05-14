defmodule RompCrmWeb.JobDeleteBar do
  @moduledoc false
  use Phoenix.Component

  attr :job, :any, required: true
  attr :delete_step, :integer, required: true
  attr :can_edit_jobs, :boolean, required: true

  def job_delete_bar(assigns) do
    ~H"""
    <%= if @can_edit_jobs do %>
      <div class="pt-3 mt-2 border-t border-base-300 space-y-2">
        <%= if @delete_step == 1 do %>
          <div class="rounded-lg border border-amber-400/60 bg-amber-500/10 px-3 py-2 text-xs text-amber-950 dark:text-amber-100">
            Step 1 of 3: You are about to delete this entire job (hours, work items, materials, and photos). This cannot be undone.
          </div>
        <% end %>
        <%= if @delete_step == 2 do %>
          <div class="rounded-lg border border-red-500/50 bg-red-500/10 px-3 py-2 text-xs text-red-900 dark:text-red-100">
            Step 2 of 3: One more click will permanently remove
            <span class="font-semibold">{@job.client_name}</span>
            and everything on this job.
          </div>
        <% end %>
        <div class="flex flex-wrap items-center gap-2">
          <%= if @delete_step < 2 do %>
            <button
              type="button"
              phx-click="job_delete_advance"
              phx-value-id={@job.id}
              class={[
                "inline-flex items-center justify-center rounded-lg px-3 py-2 text-xs font-semibold shadow-sm ring-1 ring-inset transition-colors",
                if(@delete_step == 0,
                  do: "bg-base-100 text-red-700 ring-red-300 hover:bg-red-50",
                  else: "bg-amber-100 text-amber-900 ring-amber-400 hover:bg-amber-50"
                )
              ]}
            >
              <%= if @delete_step == 0 do %>
                Delete job
              <% else %>
                Continue — step {@delete_step + 1} of 3
              <% end %>
            </button>
          <% else %>
            <button
              type="button"
              phx-click="job_delete_advance"
              phx-value-id={@job.id}
              class="inline-flex items-center justify-center rounded-lg bg-red-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-red-500"
            >
              Delete job permanently
            </button>
          <% end %>
          <%= if @delete_step > 0 do %>
            <button
              type="button"
              phx-click="job_delete_cancel"
              phx-value-id={@job.id}
              class="text-xs font-medium text-base-content/70 hover:text-base-content underline"
            >
              Cancel delete
            </button>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end
end
