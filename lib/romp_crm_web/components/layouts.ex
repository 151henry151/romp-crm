defmodule RompCrmWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RompCrmWeb, :html

  import RompCrmWeb.AppWorkspaceNav

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :content_width, :atom,
    default: :narrow,
    doc: "`:narrow` (~672px) for forms; `:wide` (~1280px) to match the Jobs list layout"

  attr :show_workspace_nav, :boolean,
    default: false,
    doc:
      "when true, show full CRM workspace links (time log, timeclock, employees, …) in the header"

  attr :current_business_id, :any, default: nil
  attr :my_businesses, :list, default: []
  attr :is_business_owner, :boolean, default: false

  slot :inner_block, required: true
  slot :header_extras

  def app(assigns) do
    assigns =
      assigns
      |> assign(:main_inner_class, main_inner_max(assigns.content_width))
      |> assign(:main_py_class, main_vertical_padding(assigns.content_width))

    ~H"""
    <header class="border-b border-base-300 bg-base-100 px-4 sm:px-6 py-2 sm:py-3">
      <div class="mx-auto max-w-screen-xl">
        <div class="flex flex-wrap items-center gap-x-2 gap-y-2">
          <a
            href={~p"/"}
            class="brand-logo-hitbox inline-flex shrink-0 focus:outline-none focus-visible:rounded-2xl focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-base-100"
          >
            <span class="brand-logo-crop block aspect-[1154/489] h-8 sm:h-9 overflow-hidden rounded-2xl">
              <img
                src={~p"/images/romp-crm-logo-main.png"}
                alt="Romp CRM"
                class="brand-logo-light block h-full w-full object-cover object-center max-w-none"
              />
              <img
                src={~p"/images/romp-crm-logo-main-dark.png"}
                alt="Romp CRM"
                class="brand-logo-dark block h-full w-full object-cover object-center max-w-none"
              />
            </span>
          </a>

          <div class="flex min-w-0 flex-1 flex-wrap items-center justify-end gap-x-2 gap-y-1 sm:justify-between">
            <div class="flex min-w-0 flex-1 items-center justify-end lg:justify-start">
              <%= if @current_scope && @current_scope.user && @show_workspace_nav do %>
                <.app_workspace_nav
                  current_business_id={@current_business_id}
                  my_businesses={@my_businesses}
                  is_business_owner={@is_business_owner}
                />
              <% else %>
                <%= if @current_scope && @current_scope.user do %>
                  <nav class="flex flex-wrap items-center justify-end gap-x-3 gap-y-1 text-sm lg:justify-start">
                    <a href={~p"/businesses"} class="link link-hover whitespace-nowrap">
                      Businesses
                    </a>
                  </nav>
                <% end %>
              <% end %>
            </div>

            <div class="flex shrink-0 items-center gap-0.5">
              <.theme_toggle />
              <%= if @current_scope && @current_scope.user do %>
                <.link
                  href={~p"/users/settings"}
                  class="btn btn-square btn-ghost btn-sm h-9 w-9 min-h-0 shrink-0 p-0 text-base-content/80 hover:bg-base-300/40"
                  aria-label="Settings"
                >
                  <.icon name="hero-cog-6-tooth" class="size-5" />
                </.link>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="btn btn-square btn-ghost btn-sm h-9 w-9 min-h-0 shrink-0 p-0 text-base-content/80 hover:bg-base-300/40"
                  aria-label="Log out"
                >
                  <.icon name="hero-arrow-right-start-on-rectangle" class="size-5" />
                </.link>
              <% end %>
            </div>
          </div>
        </div>

        <%= if @header_extras != [] do %>
          <div class="mt-2 max-w-2xl space-y-1 border-t border-base-300/60 pt-2 text-sm lg:max-w-none">
            {render_slot(@header_extras)}
          </div>
        <% end %>
      </div>
    </header>

    <main class={["px-4 sm:px-6 lg:px-8", @main_py_class]}>
      <div class={["mx-auto w-full space-y-4", @main_inner_class]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.legal_footer />

    <.flash_group flash={@flash} />
    """
  end

  defp main_inner_max(:wide), do: "max-w-screen-xl"
  defp main_inner_max(:narrow), do: "max-w-2xl"

  defp main_vertical_padding(:wide), do: "py-6"
  defp main_vertical_padding(:narrow), do: "py-12 sm:py-20"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Footer links to published Privacy Policy and Terms of Service on rompcrm.com.
  """
  def legal_footer(assigns) do
    ~H"""
    <footer class="border-t border-base-300/80 mt-auto px-4 py-8 text-center text-xs text-base-content/65">
      <nav class="flex flex-wrap justify-center gap-x-4 gap-y-1">
        <a
          href="https://rompcrm.com/privacy-policy.html"
          class="link link-hover"
          target="_blank"
          rel="noopener noreferrer"
        >
          Privacy Policy
        </a>
        <span aria-hidden="true">·</span>
        <a
          href="https://rompcrm.com/terms-of-service.html"
          class="link link-hover"
          target="_blank"
          rel="noopener noreferrer"
        >
          Terms of Service
        </a>
      </nav>
      <p class="mt-2 tabular-nums">© {Date.utc_today().year} Romp CRM</p>
    </footer>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
