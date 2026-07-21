defmodule RompCrmWeb.JobPhotosSection do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1]

  alias RompCrmWeb.JobExpandEditKeys, as: EK
  alias RompCrmWeb.PathPrefix

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :edit_keys, :any, required: true
  attr :delete_all_step, :integer, default: 0
  attr :wrapper_class, :string, default: "pt-2"

  def job_photos_section(assigns) do
    photos = assigns.job.photos || []
    edit_key = EK.photos_edit(assigns.job.id)
    editing? = editing?(assigns.edit_keys, edit_key)

    assigns =
      assigns
      |> assign(:photos, photos)
      |> assign(:edit_key, edit_key)
      |> assign(:editing?, editing?)

    ~H"""
    <div class={@wrapper_class}>
      <div class="mb-1.5 flex flex-wrap items-center justify-between gap-2">
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-1">
          <p class="font-medium text-base-content/90 text-sm">Photos:</p>
          <%= if @can_edit_jobs && @photos != [] do %>
            <%= if @editing? do %>
              <button
                type="button"
                phx-click="sort_job_photos_by_timestamp"
                phx-value-job_id={@job.id}
                class="rounded-lg border border-base-300 px-2 py-1 text-[11px] font-semibold text-base-content/80 hover:bg-base-200"
                title="Sort photos oldest to newest by upload time"
              >
                Sort by timestamp
              </button>
              <a
                href={PathPrefix.request_path("/jobs/#{@job.id}/photos/download")}
                class="rounded-lg border border-base-300 px-2 py-1 text-[11px] font-semibold text-base-content/80 hover:bg-base-200"
                title="Download all photos on this job as a ZIP archive"
              >
                Download all (zip archive)
              </a>
              <button
                type="button"
                phx-click="job_expand_edit_cancel"
                phx-value-key={@edit_key}
                class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-base-content/50 hover:bg-base-300/40"
                aria-label="Done editing photos"
                title="Done editing"
              >
                <.icon name="hero-x-mark" class="size-3.5" />
              </button>
            <% else %>
              <button
                type="button"
                phx-click="job_expand_edit_start"
                phx-value-key={@edit_key}
                data-job-expand-edit-start={@edit_key}
                class="btn btn-square btn-ghost btn-xs h-7 w-7 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
                aria-label="Edit photos"
                title="Edit order or delete photos"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>
              <button
                type="button"
                phx-click="request_delete_all_job_photos"
                phx-value-job_id={@job.id}
                class="btn btn-square btn-ghost btn-xs h-6 w-6 min-h-0 shrink-0 border border-red-500/35 p-0 text-sm font-semibold leading-none text-red-500 hover:bg-red-500/15 hover:text-red-400"
                aria-label="Delete all photos"
                title="Delete all photos"
              >
                ×
              </button>
            <% end %>
          <% end %>
        </div>
        <%= if @can_edit_jobs do %>
          <button
            type="button"
            phx-click="open_add_photos"
            phx-value-job_id={@job.id}
            class="shrink-0 btn btn-brand btn-xs px-3 py-1.5 text-xs font-semibold"
          >
            Add photos…
          </button>
        <% end %>
      </div>

      <%= if @delete_all_step > 0 && @can_edit_jobs do %>
        <%= if @delete_all_step == 1 do %>
          <div class="mb-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-950">
            <p class="font-medium">Delete all {length(@photos)} photo(s) on this job?</p>
            <p class="mt-0.5 text-xs text-amber-900/80">
              Step 1 of 2 — continue only if you want to remove every photo.
            </p>
            <div class="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="advance_delete_all_job_photos"
                phx-value-job_id={@job.id}
                class="rounded-lg bg-amber-600 px-3 py-1 text-xs font-semibold text-white hover:bg-amber-500"
              >
                Continue
              </button>
              <button
                type="button"
                phx-click="cancel_delete_all_job_photos"
                class="rounded-lg border border-amber-400 px-3 py-1 text-xs font-medium text-amber-950 hover:bg-amber-100"
              >
                Cancel
              </button>
            </div>
          </div>
        <% end %>
        <%= if @delete_all_step == 2 do %>
          <div class="mb-2 rounded-lg border border-red-400 bg-red-50 px-3 py-2 text-sm text-red-950">
            <p class="font-medium">Permanently delete all {length(@photos)} photo(s)?</p>
            <p class="mt-0.5 text-xs text-red-900/80">
              Step 2 of 2 — this cannot be undone. Download a copy first if you might need these files.
            </p>
            <div class="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="delete_all_job_photos"
                phx-value-job_id={@job.id}
                class="rounded-lg bg-red-600 px-3 py-1 text-xs font-semibold text-white hover:bg-red-500"
              >
                Yes, delete all photos
              </button>
              <button
                type="button"
                phx-click="cancel_delete_all_job_photos"
                class="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-950 hover:bg-red-100"
              >
                Cancel
              </button>
            </div>
          </div>
        <% end %>
      <% end %>

      <%= if @photos != [] do %>
        <%= if @editing? && @can_edit_jobs do %>
          <div
            data-job-expand-edit-surface
            data-job-expand-edit-key={@edit_key}
            data-job-expand-no-dirty="true"
            class="flex flex-col gap-2"
          >
            <%= for {ph, idx} <- Enum.with_index(@photos, 1) do %>
              <div class="flex items-center gap-2">
                <div class="flex shrink-0 flex-col gap-0.5">
                  <button
                    type="button"
                    phx-click="move_job_photo"
                    phx-value-job_id={@job.id}
                    phx-value-photo_id={ph.id}
                    phx-value-direction="up"
                    disabled={idx == 1}
                    class={[
                      "rounded border px-1 py-0.5 text-[10px] leading-none",
                      if(idx == 1,
                        do: "border-base-200 text-base-content/30 cursor-not-allowed",
                        else: "border-base-300 text-base-content/70 hover:bg-base-200"
                      )
                    ]}
                    aria-label="Move photo earlier"
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    phx-click="move_job_photo"
                    phx-value-job_id={@job.id}
                    phx-value-photo_id={ph.id}
                    phx-value-direction="down"
                    disabled={idx == length(@photos)}
                    class={[
                      "rounded border px-1 py-0.5 text-[10px] leading-none",
                      if(idx == length(@photos),
                        do: "border-base-200 text-base-content/30 cursor-not-allowed",
                        else: "border-base-300 text-base-content/70 hover:bg-base-200"
                      )
                    ]}
                    aria-label="Move photo later"
                  >
                    ↓
                  </button>
                </div>
                <button
                  type="button"
                  phx-click="open_photo_viewer"
                  phx-value-job_id={@job.id}
                  phx-value-photo_id={ph.id}
                  class="group relative shrink-0 overflow-hidden rounded border border-base-300 focus:outline-none focus:ring-2 focus:ring-primary/40"
                >
                  <img
                    src={RompCrmWeb.PathPrefix.static_upload_path(ph.relative_path)}
                    alt="Job photo"
                    class="h-16 w-16 sm:h-20 sm:w-20 object-cover group-hover:opacity-90"
                  />
                  <span class="sr-only">View photo {idx}</span>
                </button>
                <button
                  type="button"
                  phx-click="delete_job_photo"
                  phx-value-job_id={@job.id}
                  phx-value-photo_id={ph.id}
                  data-confirm="Delete this photo?"
                  class="btn btn-square btn-ghost btn-xs h-6 w-6 min-h-0 shrink-0 border border-red-500/35 p-0 text-sm font-semibold leading-none text-red-500 hover:bg-red-500/15 hover:text-red-400"
                  aria-label="Delete photo"
                >
                  ×
                </button>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="flex flex-wrap gap-2">
            <%= for ph <- @photos do %>
              <button
                type="button"
                phx-click="open_photo_viewer"
                phx-value-job_id={@job.id}
                phx-value-photo_id={ph.id}
                class="group relative shrink-0 overflow-hidden rounded border border-base-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <img
                  src={RompCrmWeb.PathPrefix.static_upload_path(ph.relative_path)}
                  alt="Job photo"
                  class="h-16 w-16 sm:h-20 sm:w-20 object-cover group-hover:opacity-90"
                />
              </button>
            <% end %>
          </div>
        <% end %>
      <% else %>
        <p class="text-xs text-base-content/60">No photos yet.</p>
      <% end %>
    </div>
    """
  end

  defp editing?(keys, key) when is_struct(keys, MapSet), do: MapSet.member?(keys, key)
  defp editing?(_, _), do: false
end
