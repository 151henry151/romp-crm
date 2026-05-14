defmodule RompCrmWeb.AppWorkspaceNav do
  @moduledoc """
  Shared workspace navigation (jobs area): job list, time log, timeclock, employees, businesses.
  Desktop: pill-style links plus **Support**. Mobile: icon-only **hamburger** drawer with the same links and **Support**.
  """
  use Phoenix.Component
  use Gettext, backend: RompCrmWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: RompCrmWeb.Endpoint,
    router: RompCrmWeb.Router,
    statics: RompCrmWeb.static_paths()

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import RompCrmWeb.CoreComponents

  attr :current_business_id, :any, default: nil
  attr :my_businesses, :list, default: []
  attr :is_business_owner, :boolean, default: false

  def app_workspace_nav(assigns) do
    ~H"""
    <div class="flex w-full min-w-0 flex-col items-end gap-2 lg:w-auto lg:flex-row lg:items-center lg:justify-start lg:gap-3">
      <%!-- Desktop --%>
      <div class="hidden flex-wrap items-center gap-x-2 gap-y-1.5 lg:flex">
        <%= if @my_businesses != [] && length(@my_businesses) > 1 do %>
          <.business_switcher
            my_businesses={@my_businesses}
            current_business_id={@current_business_id}
          />
        <% end %>
        <.nav_links is_business_owner={@is_business_owner} />
      </div>

      <%!-- Mobile menu --%>
      <details class="group relative lg:hidden">
        <summary
          class="btn btn-square btn-ghost btn-sm h-9 w-9 min-h-0 shrink-0 list-none border border-base-300 p-0 [&::-webkit-details-marker]:hidden"
          aria-label="Open navigation menu"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </summary>
        <div class="absolute right-0 z-[200] mt-1 flex min-w-[12rem] max-w-[min(100vw-2rem,20rem)] flex-col gap-1.5 rounded-lg border border-base-300 bg-base-100 p-2 shadow-lg">
          <%= if @my_businesses != [] && length(@my_businesses) > 1 do %>
            <div class="mb-1 border-b border-base-300 pb-2">
              <.business_switcher
                my_businesses={@my_businesses}
                current_business_id={@current_business_id}
                compact={true}
              />
            </div>
          <% end %>
          <.nav_links is_business_owner={@is_business_owner} mobile={true} />
        </div>
      </details>
    </div>
    """
  end

  attr :my_businesses, :list, required: true
  attr :current_business_id, :any, default: nil
  attr :compact, :boolean, default: false

  def business_switcher(assigns) do
    wrap_class =
      if assigns.compact,
        do: "flex flex-col gap-1",
        else: "flex flex-wrap items-center gap-2"

    select_id =
      if assigns.compact,
        do: "app-nav-business-switch-mobile",
        else: "app-nav-business-switch-desktop"

    assigns =
      assigns
      |> assign(:wrap_class, wrap_class)
      |> assign(:select_id, select_id)

    ~H"""
    <form action={~p"/business/switch"} method="post" class={@wrap_class}>
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <label for={@select_id} class="sr-only">Business</label>
      <select
        id={@select_id}
        name="business_id"
        class={[
          "select select-bordered select-sm max-w-full bg-base-100",
          @compact && "w-full"
        ]}
        onchange="this.form.requestSubmit()"
      >
        <%= for b <- @my_businesses do %>
          <option value={b.id} selected={b.id == @current_business_id}>{b.name}</option>
        <% end %>
      </select>
    </form>
    """
  end

  attr :is_business_owner, :boolean, default: false
  attr :mobile, :boolean, default: false

  def nav_links(assigns) do
    mobile_attrs =
      if assigns.mobile,
        do: %{"onclick" => "this.closest('details')?.removeAttribute('open')"},
        else: %{}

    pill = pill_nav_classes(assigns.mobile)
    assigns = assigns |> assign(:mobile_attrs, mobile_attrs) |> assign(:pill, pill)

    ~H"""
    <.link navigate={~p"/"} class={@pill} {@mobile_attrs}>
      Job list
    </.link>
    <.link navigate={~p"/time-log"} class={@pill} {@mobile_attrs}>
      Job time log
    </.link>
    <.link navigate={~p"/my-timeclock"} class={@pill} {@mobile_attrs}>
      Workday timeclock
    </.link>
    <%= if @is_business_owner do %>
      <.link navigate={~p"/employees"} class={@pill} {@mobile_attrs}>
        Employees
      </.link>
    <% end %>
    <.link navigate={~p"/businesses"} class={@pill} {@mobile_attrs}>
      Businesses
    </.link>
    <.link navigate={~p"/support"} class={@pill} {@mobile_attrs}>
      Support
    </.link>
    """
  end

  defp pill_nav_classes(true) do
    Enum.join(
      [
        "block w-full text-center no-underline rounded-lg border border-emerald-600/35",
        "bg-emerald-500/10 px-3 py-2 text-sm font-semibold text-emerald-800",
        "hover:bg-emerald-500/15",
        "dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-100 dark:hover:bg-emerald-500/25"
      ],
      " "
    )
  end

  defp pill_nav_classes(false) do
    Enum.join(
      [
        "inline-flex shrink-0 items-center justify-center no-underline rounded-lg border border-emerald-600/35",
        "bg-emerald-500/10 px-3 py-1.5 text-sm font-semibold text-emerald-800",
        "hover:bg-emerald-500/15",
        "dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-100 dark:hover:bg-emerald-500/25"
      ],
      " "
    )
  end
end
