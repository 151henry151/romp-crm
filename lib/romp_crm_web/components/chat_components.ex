defmodule RompCrmWeb.ChatComponents do
  @moduledoc """
  Reusable messenger-style UI for conversation threads (agent chat today; client SMS threads later).
  """
  use Phoenix.Component

  attr :rows, :list, required: true
  attr :id, :string, default: "chat-thread"

  def chat_thread(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-2 px-0.5 py-1">
      <%= for row <- @rows do %>
        <.chat_bubble row={row} />
      <% end %>
    </div>
    """
  end

  attr :row, :map, required: true

  def chat_bubble(assigns) do
    text = assigns.row.text
    photos = assigns.row.photos || []

    has_content? = text_present?(text) or photos != []

    assigns =
      assigns
      |> assign(:has_content?, has_content?)
      |> assign(:row, Map.put(assigns.row, :photos, photos))

    ~H"""
    <%= if @has_content? do %>
      <div class={[
        "flex w-full flex-col",
        if(@row.side == :right, do: "items-end", else: "items-start")
      ]}>
        <div class="mb-0.5 px-1 text-[10px] font-medium tracking-wide text-base-content/55">
          {@row.label}
        </div>
        <div class={[
          "max-w-[min(85%,20rem)] break-words text-[15px] leading-snug",
          "px-3 py-1.5 shadow-sm",
          bubble_shape(@row.side),
          bubble_tone(@row.role)
        ]}>
          <%= if text_present?(@row.text) do %>
            <span class="whitespace-pre-wrap">{@row.text}</span>
          <% end %>
          <%= if @row.photos != [] do %>
            <div class={if(text_present?(@row.text), do: "mt-1", else: "") <> " flex flex-wrap gap-1.5"}>
              <%= for url <- @row.photos do %>
                <a href={url} target="_blank" rel="noopener noreferrer" class="block shrink-0 overflow-hidden rounded-xl">
                  <img
                    src={url}
                    alt="Attached photo"
                    class="max-h-36 max-w-full object-cover"
                  />
                </a>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :form_id, :string, default: "chat-compose-form"
  attr :placeholder, :string, default: "Message the RompCRM agent…"
  attr :disabled, :boolean, default: false
  attr :submit_event, :string, default: "chat_send"
  attr :attach_enabled, :boolean, default: false
  attr :upload_url, :string, default: nil
  attr :pending_photos, :list, default: []

  def chat_compose(assigns) do
    ~H"""
    <form
      id={@form_id}
      phx-submit={@submit_event}
      phx-reset
      phx-hook="ChatCompose"
      data-upload-url={@upload_url}
      data-attach-enabled={to_string(@attach_enabled)}
      class="flex flex-col gap-2 border-t border-base-300 pt-3"
    >
      <%= if @pending_photos != [] do %>
        <div class="flex flex-wrap gap-2 px-0.5" data-role="pending-photos">
          <%= for {url, idx} <- Enum.with_index(@pending_photos) do %>
            <div class="relative">
              <img src={url} alt="Pending attachment" class="h-16 w-16 rounded-lg object-cover ring-1 ring-base-300" />
              <button
                type="button"
                phx-click="chat_remove_pending_photo"
                phx-value-index={idx}
                class="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-base-100 text-xs font-bold text-base-content shadow ring-1 ring-base-300"
                aria-label="Remove photo"
              >
                ×
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
      <div class="flex items-end gap-2">
        <%= if @attach_enabled and is_binary(@upload_url) do %>
          <label class={[
            "btn btn-ghost btn-sm btn-square shrink-0",
            @disabled && "btn-disabled pointer-events-none opacity-50"
          ]}>
            <span class="sr-only">Attach image</span>
            <input
              type="file"
              accept="image/*"
              class="hidden"
              data-role="chat-attach-input"
              disabled={@disabled}
            />
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5" aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="m18.375 12.739-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.003.003-.003.002a2.25 2.25 0 0 1-3.18-3.182l.002-.003.003-.002L15.75 5.25"
              />
            </svg>
          </label>
        <% end %>
        <label class="sr-only" for={"#{@form_id}-input"}>Message</label>
        <textarea
          id={"#{@form_id}-input"}
          name="message"
          rows="2"
          placeholder={@placeholder}
          disabled={@disabled}
          class="textarea textarea-bordered min-h-[2.75rem] max-h-32 flex-1 resize-none text-sm"
        ></textarea>
        <button type="submit" class="btn btn-primary btn-sm shrink-0" disabled={@disabled}>
          Send
        </button>
      </div>
      <p data-role="chat-attach-status" class="min-h-[1rem] px-0.5 text-xs text-base-content/60"></p>
    </form>
    """
  end

  attr :id, :string, default: "chat-typing-indicator"
  attr :label, :string, default: "RompCRM agent"

  def chat_typing_indicator(assigns) do
    ~H"""
    <div id={@id} class="mt-2 flex w-full flex-col items-start" aria-live="polite" aria-label={"#{@label} is typing"}>
      <div class="mb-0.5 px-1 text-[10px] font-medium tracking-wide text-base-content/55">
        {@label}
      </div>
      <div class={[
        "max-w-[min(85%,20rem)] px-3 py-2 text-sm leading-snug text-base-content/70",
        "rounded-[1.125rem] rounded-bl-[0.35rem] shadow-sm",
        bubble_tone(:agent)
      ]}>
        <span class="chat-typing-dots">RompCRM is typing</span>
      </div>
    </div>
    """
  end

  defp text_present?(text) when is_binary(text), do: text != ""
  defp text_present?(_), do: false

  defp bubble_shape(:right), do: "rounded-[1.125rem] rounded-br-[0.35rem]"
  defp bubble_shape(:left), do: "rounded-[1.125rem] rounded-bl-[0.35rem]"
  defp bubble_shape(_), do: "rounded-[1.125rem]"

  defp bubble_tone(:agent) do
    "bg-neutral-200 text-neutral-900 dark:bg-neutral-700 dark:text-neutral-50"
  end

  defp bubble_tone(:self) do
    "bg-emerald-600 text-white dark:bg-emerald-500 dark:text-white"
  end

  defp bubble_tone(:employee) do
    "bg-sky-600 text-white dark:bg-sky-500 dark:text-white"
  end

  defp bubble_tone(:customer) do
    "bg-base-200 text-base-content dark:bg-neutral-600 dark:text-neutral-50"
  end

  defp bubble_tone(_), do: "bg-base-300 text-base-content"
end
