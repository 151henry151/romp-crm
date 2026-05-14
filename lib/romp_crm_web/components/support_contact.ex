defmodule RompCrmWeb.SupportContact do
  @moduledoc false
  use Phoenix.Component

  @doc """
  Expandable **Support** control with telephone number for live help.
  """
  def support_contact(assigns) do
    ~H"""
    <details class="relative">
      <summary class="list-none cursor-pointer select-none rounded-lg border border-emerald-600/35 bg-emerald-500/10 px-3 py-1.5 text-sm font-semibold text-emerald-800 hover:bg-emerald-500/15 dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-100 dark:hover:bg-emerald-500/25 [&::-webkit-details-marker]:hidden">
        Support
      </summary>
      <div class="absolute right-0 z-[100] mt-2 w-[min(18rem,calc(100vw-2rem))] rounded-lg border border-base-300 bg-base-100 p-3 shadow-lg">
        <a
          href="tel:+18024587299"
          class="block text-lg font-semibold text-primary hover:underline tabular-nums"
        >
          802-458-7299
        </a>
        <p class="mt-1.5 text-xs leading-snug text-base-content/75">
          call to speak with a live person 24/7
        </p>
      </div>
    </details>
    """
  end
end
