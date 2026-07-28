defmodule RompCrmWeb.JobPrintModal do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [modal: 1]

  alias Phoenix.LiveView.JS
  alias RompCrmWeb.PathPrefix

  attr :job_id, :integer, required: true
  attr :client_name, :string, required: true

  def job_print_modal(assigns) do
    ~H"""
    <.modal id="job-print-modal" show on_cancel={JS.push("close_print_job")}>
      <div class="pr-8 max-w-md">
        <h2 id="job-print-modal-title" class="text-lg font-semibold text-base-content">
          Print job
        </h2>
        <p class="mt-1 text-sm text-base-content/70">
          Download a PDF for
          <span class="font-medium text-base-content/90">{@client_name}</span>.
          Include job photos in the PDF?
        </p>

        <div class="mt-5 flex flex-col gap-2 sm:flex-row sm:flex-wrap">
          <a
            href={PathPrefix.request_path("/jobs/#{@job_id}/print")}
            class="btn btn-brand btn-sm"
          >
            With photos
          </a>
          <a
            href={PathPrefix.request_path("/jobs/#{@job_id}/print?photos=0")}
            class="btn btn-outline btn-sm"
          >
            Without photos
          </a>
          <button type="button" phx-click="close_print_job" class="btn btn-ghost btn-sm">
            Cancel
          </button>
        </div>
      </div>
    </.modal>
    """
  end
end
