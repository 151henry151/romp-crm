defmodule RompCrmWeb.JobPhotoViewerModal do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS
  alias RompCrmWeb.PathPrefix

  attr :job_id, :integer, required: true
  attr :photo_id, :integer, required: true
  attr :photos, :list, required: true
  attr :position, :integer, required: true
  attr :total, :integer, required: true

  def job_photo_viewer_modal(assigns) do
    photo = Enum.find(assigns.photos, &(&1.id == assigns.photo_id))
    assigns = assign(assigns, :photo, photo)
    prev_id = neighbor_photo_id(assigns.photos, assigns.position, -1)
    next_id = neighbor_photo_id(assigns.photos, assigns.position, 1)
    assigns = assign(assigns, :prev_id, prev_id)
    assigns = assign(assigns, :next_id, next_id)

    ~H"""
    <%= if @photo do %>
      <div
        id="job-photo-viewer-modal"
        class="fixed inset-0 z-50"
        role="dialog"
        aria-modal="true"
        aria-label={"Job photo #{@position} of #{@total}"}
        phx-window-keydown={JS.push("close_photo_viewer")}
        phx-key="escape"
      >
        <button
          type="button"
          phx-click="close_photo_viewer"
          class="absolute inset-0 z-0 bg-black"
          aria-label="Close photo viewer"
        />

        <div
          id={"job-photo-viewer-#{@job_id}"}
          phx-hook="JobPhotoViewer"
          data-photo-id={@photo.id}
          class="absolute inset-0 z-10"
        >
          <button
            type="button"
            phx-click="close_photo_viewer"
            class="absolute top-3 right-3 z-30 rounded-full p-2 text-white/75 hover:bg-white/10 hover:text-white"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>

          <button
            :if={@prev_id}
            type="button"
            phx-click="photo_viewer_nav"
            phx-value-job_id={@job_id}
            phx-value-photo_id={@prev_id}
            class="absolute left-2 top-1/2 z-30 -translate-y-1/2 rounded-full p-1.5 text-white/70 hover:bg-white/10 hover:text-white sm:left-4 sm:p-2"
            aria-label="Previous photo"
          >
            <.icon name="hero-chevron-left" class="size-6 sm:size-7" />
          </button>

          <button
            :if={@next_id}
            type="button"
            phx-click="photo_viewer_nav"
            phx-value-job_id={@job_id}
            phx-value-photo_id={@next_id}
            class="absolute right-2 top-1/2 z-30 -translate-y-1/2 rounded-full p-1.5 text-white/70 hover:bg-white/10 hover:text-white sm:right-4 sm:p-2"
            aria-label="Next photo"
          >
            <.icon name="hero-chevron-right" class="size-6 sm:size-7" />
          </button>

          <div
            data-role="zoom-stage"
            class="absolute inset-0 flex items-center justify-center overflow-hidden touch-none"
          >
            <img
              data-role="zoom-image"
              src={PathPrefix.static_upload_path(@photo.relative_path)}
              alt="Job photo"
              class="max-h-[100dvh] max-w-[100vw] origin-center select-none object-contain transition-transform duration-75"
              draggable="false"
            />
          </div>

          <a
            href={PathPrefix.request_path("/jobs/#{@job_id}/photos/#{@photo.id}/download")}
            class="absolute bottom-3 right-3 z-30 rounded-full p-2 text-white/75 hover:bg-white/10 hover:text-white"
            aria-label="Download photo"
            title="Download photo"
          >
            <.icon name="hero-arrow-down-tray" class="size-5" />
          </a>
        </div>
      </div>
    <% end %>
    """
  end

  defp neighbor_photo_id(photos, position, delta) when is_list(photos) and is_integer(position) do
    case Enum.at(photos, position - 1 + delta) do
      nil -> nil
      photo -> photo.id
    end
  end
end
