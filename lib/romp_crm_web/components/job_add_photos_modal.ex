defmodule RompCrmWeb.JobAddPhotosModal do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1, modal: 1]

  alias Phoenix.LiveView.JS

  attr :job_id, :integer, required: true
  attr :client_name, :string, required: true
  attr :saved_count, :integer, required: true
  attr :upload_url, :string, required: true

  def job_add_photos_modal(assigns) do
    ~H"""
    <.modal
      id="job-add-photos-modal"
      show
      cancel_on_click_away={false}
      on_cancel={JS.push("close_add_photos")}
    >
      <div class="pr-8 max-w-lg">
        <h2 id="job-add-photos-modal-title" class="text-lg font-semibold text-base-content">
          Add photos
        </h2>
        <p class="mt-1 text-sm text-base-content/70">
          For <span class="font-medium text-base-content/90">{@client_name}</span>.
          Photos save automatically when selected or captured.
        </p>

        <div
          id={"job-photo-picker-#{@job_id}"}
          phx-hook="JobPhotoUpload"
          phx-update="ignore"
          data-upload-url={@upload_url}
          class="mt-5 rounded-lg border-2 border-dashed border-base-300 bg-base-200/40 p-4"
        >
          <div class="flex flex-col sm:flex-row gap-2">
            <label class="relative flex flex-1 cursor-pointer items-center justify-center gap-2 overflow-hidden rounded-lg bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content hover:opacity-90">
              <input
                data-role="gallery-input"
                type="file"
                accept="image/*"
                multiple
                class="absolute inset-0 z-10 h-full w-full cursor-pointer opacity-0"
              />
              <.icon name="hero-photo" class="h-5 w-5 pointer-events-none" />
              <span class="pointer-events-none">Choose from gallery</span>
            </label>

            <%!-- Mobile: tap opens native camera directly via overlaid file input --%>
            <label class="relative flex flex-1 cursor-pointer items-center justify-center gap-2 overflow-hidden rounded-lg border border-base-300 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content hover:bg-base-200 sm:hidden">
              <input
                data-role="camera-input"
                type="file"
                accept="image/*"
                capture="environment"
                class="absolute inset-0 z-10 h-full w-full cursor-pointer opacity-0"
              />
              <.icon name="hero-camera" class="h-5 w-5 pointer-events-none" />
              <span class="pointer-events-none">Use camera</span>
            </label>

            <%!-- Desktop: webcam capture panel --%>
            <button
              type="button"
              data-role="desktop-camera-btn"
              class="hidden sm:inline-flex flex-1 items-center justify-center gap-2 rounded-lg border border-base-300 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content hover:bg-base-200"
            >
              <.icon name="hero-camera" class="h-5 w-5" />
              Use camera
            </button>
          </div>

          <div data-role="webcam-panel" class="hidden mt-4 space-y-3">
            <video
              data-role="webcam-video"
              class="hidden w-full max-h-64 rounded-lg border border-base-300 bg-black object-contain"
              playsinline
              muted
              autoplay
            />
            <canvas data-role="webcam-canvas" class="hidden" />
            <button
              type="button"
              data-role="webcam-capture"
              class="hidden btn btn-primary btn-xs"
            >
              Capture photo
            </button>
          </div>

          <p data-role="status" class="mt-3 min-h-[1.25rem] text-xs text-base-content/60" />
        </div>

        <%= if @saved_count > 0 do %>
          <p class="mt-3 text-sm font-medium text-success">
            {if @saved_count == 1,
              do: "1 photo saved on this job.",
              else: "#{@saved_count} photos saved on this job."}
          </p>
        <% end %>

        <div class="mt-5 flex flex-wrap gap-2">
          <button type="button" phx-click="close_add_photos" class="btn btn-primary btn-sm">
            Done
          </button>
        </div>
      </div>
    </.modal>
    """
  end
end
