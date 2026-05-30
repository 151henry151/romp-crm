defmodule RompCrmWeb.ChatComponents do
  @moduledoc """
  Reusable messenger-style UI for conversation threads (agent chat today; client SMS threads later).
  """
  use Phoenix.Component

  attr :rows, :list, required: true
  attr :id, :string, default: "chat-thread"

  def chat_thread(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-2 overflow-y-auto px-0.5 py-1">
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

  def chat_compose(assigns) do
    ~H"""
    <form
      id={@form_id}
      phx-submit="chat_send"
      phx-reset
      phx-hook="ChatCompose"
      class="flex items-end gap-2 border-t border-base-300 pt-3"
    >
      <label class="sr-only" for={"#{@form_id}-input"}>Message</label>
      <textarea
        id={"#{@form_id}-input"}
        name="message"
        rows="2"
        placeholder={@placeholder}
        disabled={@disabled}
        class="textarea textarea-bordered min-h-[2.75rem] flex-1 resize-y text-sm"
      ></textarea>
      <button type="submit" class="btn btn-primary btn-sm shrink-0" disabled={@disabled}>
        Send
      </button>
    </form>
    """
  end

  attr :id, :string, default: "chat-typing-indicator"

  def chat_typing_indicator(assigns) do
    ~H"""
    <div id={@id} class="mt-2 flex w-full flex-col items-start" aria-live="polite" aria-label="RompCRM agent is typing">
      <div class="mb-0.5 px-1 text-[10px] font-medium tracking-wide text-base-content/55">
        RompCRM agent
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

  defp bubble_tone(_), do: "bg-base-300 text-base-content"
end
