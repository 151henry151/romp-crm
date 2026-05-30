defmodule RompCrmWeb.PhoneFieldComponent do
  @moduledoc false
  use Phoenix.Component

  alias RompCrm.ContactInfo

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: "input input-bordered input-sm"
  attr :select_class, :string, default: "select select-bordered select-sm"
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(form disabled required)

  def phone_field(assigns) do
    {dial_code, national} = ContactInfo.split_phone(assigns.value)

    assigns =
      assigns
      |> assign(:dial_code, dial_code)
      |> assign(:national, national)
      |> assign(:national_display, ContactInfo.format_national_display(dial_code, national))
      |> assign(:countries, ContactInfo.countries())
      |> assign(:placeholder, ContactInfo.national_placeholder(dial_code))
      |> assign(:error_messages, Enum.map(assigns.errors, &format_error/1))

    ~H"""
    <div class={if @label, do: "fieldset mb-2", else: "min-w-0 w-full"}>
      <span :if={@label} class="label mb-1 block">{@label}</span>
      <div
        id={@id}
        phx-hook="PhoneField"
        class="flex min-w-0 w-full items-center gap-2"
        data-initial-value={@value || ""}
      >
        <input type="hidden" name={@name} value={@value || ""} data-phone-stored {@rest} />
        <select
          data-phone-dial
          aria-label="Country code"
          class={[@select_class, "w-[6.75rem] shrink-0 px-1 text-xs"]}
        >
          <%= for {label, code} <- @countries do %>
            <option value={code} selected={code == @dial_code}>{label}</option>
          <% end %>
        </select>
        <input
          type="tel"
          data-phone-national
          value={@national_display}
          placeholder={@placeholder}
          autocomplete="tel-national"
          inputmode="tel"
          class={[@class, "min-w-0 flex-1", @error_messages != [] && "input-error"]}
        />
      </div>
      <p :for={msg <- @error_messages} class="mt-1 text-sm text-error">{msg}</p>
    </div>
    """
  end

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
