defmodule RompCrmWeb.JobPhotosSection do
  @moduledoc false
  use Phoenix.Component

  alias RompCrmWeb.PathPrefix

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :wrapper_class, :string, default: "pt-2"

  def job_photos_section(assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <div class="flex flex-wrap items-center justify-between gap-2 mb-1.5">
        <p class="font-medium text-base-content/90 text-sm">Photos:</p>
        <%= if @can_edit_jobs do %>
          <button
            type="button"
            phx-click="open_add_photos"
            phx-value-job_id={@job.id}
            class="shrink-0 rounded-lg border border-blue-600 px-3 py-1.5 text-xs font-semibold text-blue-600 hover:bg-blue-50"
          >
            Add photos…
          </button>
        <% end %>
      </div>
      <%= if @job.photos != [] && @job.photos do %>
        <div class="flex flex-wrap gap-2">
          <%= for ph <- @job.photos do %>
            <a
              href={PathPrefix.static_upload_path(ph.relative_path)}
              target="_blank"
              rel="noopener noreferrer"
            >
              <img
                src={PathPrefix.static_upload_path(ph.relative_path)}
                alt="Job photo"
                class="h-16 w-16 sm:h-20 sm:w-20 object-cover rounded border border-base-300"
              />
            </a>
          <% end %>
        </div>
      <% else %>
        <p class="text-xs text-base-content/60">No photos yet.</p>
      <% end %>
    </div>
    """
  end
end
