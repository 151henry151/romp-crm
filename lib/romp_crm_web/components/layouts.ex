defmodule RompCrmWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RompCrmWeb, :html

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

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:main_inner_class, main_inner_max(assigns.content_width))
      |> assign(:main_py_class, main_vertical_padding(assigns.content_width))

    ~H"""
    <header class="border-b border-base-300 bg-base-100 px-4 sm:px-6 py-4">
      <div class="mx-auto flex max-w-screen-xl flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0 shrink">
          <a
            href={~p"/"}
            class="brand-logo-hitbox inline-flex focus:outline-none focus-visible:rounded-2xl focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-base-100"
          >
            <span class="brand-logo-crop block aspect-[1154/489] h-10 sm:h-12 overflow-hidden rounded-2xl">
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
        </div>
        <nav class="flex w-full min-w-0 flex-wrap items-center gap-x-3 gap-y-2 sm:w-auto sm:justify-end">
          <%= if @current_scope && @current_scope.user do %>
            <a href={~p"/businesses"} class="link link-hover shrink-0 text-sm whitespace-nowrap">
              Businesses
            </a>
            <a href={~p"/users/settings"} class="link link-hover shrink-0 text-sm whitespace-nowrap">
              Settings
            </a>
          <% end %>
          <div class="shrink-0 [&_details]:max-w-[calc(100vw-2rem)]">
            <.support_contact />
          </div>
          <div class="shrink-0">
            <.theme_toggle />
          </div>
        </nav>
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
