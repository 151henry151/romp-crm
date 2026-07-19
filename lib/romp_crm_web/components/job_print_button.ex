defmodule RompCrmWeb.JobPrintButton do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1]

  alias RompCrmWeb.PathPrefix

  attr :job, :any, required: true
  attr :class, :string, default: nil

  def job_print_button(assigns) do
    ~H"""
    <a
      href={PathPrefix.request_path("/jobs/#{@job.id}/print")}
      class={[
        "inline-flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold text-base-content/85 shadow-sm ring-1 ring-inset ring-base-300/60 hover:bg-base-200",
        @class
      ]}
      title="Download a PDF of this job’s details"
      onclick="event.stopPropagation()"
    >
      <.icon name="hero-printer" class="size-4 shrink-0 opacity-80" />
      Print job
    </a>
    """
  end
end
