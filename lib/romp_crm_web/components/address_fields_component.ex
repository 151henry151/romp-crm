defmodule RompCrmWeb.AddressFieldsComponent do
  @moduledoc """
  Structured service + optional billing address fields with Google Places hook.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :name_prefix, :string, default: "job"
  attr :target, :any, default: nil
  attr :values, :map, required: true
  attr :show_billing?, :boolean, default: true
  attr :suggestion, :map, default: nil

  def address_fields(assigns) do
    billing_different? =
      assigns.values
      |> Map.get("billing_address_different")
      |> truthy?()

    assigns =
      assigns
      |> assign(:billing_different?, billing_different?)
      |> assign(:maps_configured?, RompCrm.GoogleMaps.configured?())

    ~H"""
    <div class="space-y-4">
      <div
        id={"#{@id}-service"}
        phx-hook="GoogleAddress"
        phx-update="ignore"
        phx-target={@target}
        data-prefix={@name_prefix}
      >
        <div class="space-y-3 rounded-lg border border-base-300 bg-base-200/20 p-3">
          <p class="text-sm font-medium text-base-content">Service address</p>
          <.address_lines prefix={@name_prefix} part="service" values={@values} />
          <%= if @maps_configured? do %>
            <button type="button" data-address-validate="service" class="btn btn-brand btn-xs">
              Check address
            </button>
          <% end %>
        </div>
      </div>

      <%= if @show_billing? do %>
        <label class="flex cursor-pointer items-start gap-2 text-sm">
          <input type="hidden" name={"#{@name_prefix}[billing_address_different]"} value="false" />
          <input
            type="checkbox"
            name={"#{@name_prefix}[billing_address_different]"}
            value="true"
            checked={@billing_different?}
            class="checkbox checkbox-sm mt-0.5"
          />
          <span class="text-base-content">Billing address is different from service address</span>
        </label>

        <%= if @billing_different? do %>
          <div
            id={"#{@id}-billing"}
            phx-hook="GoogleAddress"
            phx-update="ignore"
            phx-target={@target}
            data-prefix={@name_prefix}
          >
            <div class="space-y-3 rounded-lg border border-base-300 bg-base-200/20 p-3">
              <p class="text-sm font-medium text-base-content">Billing address</p>
              <.address_lines prefix={@name_prefix} part="billing" values={@values} />
              <%= if @maps_configured? do %>
                <button type="button" data-address-validate="billing" class="btn btn-brand btn-xs">
                  Check billing address
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>

      <%= if @suggestion && @suggestion["part"] == "service" do %>
        <.address_suggestion_panel suggestion={@suggestion} target={@target} />
      <% end %>

      <%= if @suggestion && @suggestion["part"] == "billing" do %>
        <.address_suggestion_panel suggestion={@suggestion} target={@target} />
      <% end %>
    </div>
    """
  end

  attr :prefix, :string, required: true
  attr :part, :string, required: true
  attr :values, :map, required: true

  defp address_lines(assigns) do
    {line1, line2, city, state, postal, line1_id} =
      if assigns.part == "billing" do
        {"billing_address_line1", "billing_address_line2", "billing_city", "billing_state",
         "billing_postal_code", "#{assigns.prefix}-billing-line1"}
      else
        {"address_line1", "address_line2", "city", "state", "postal_code",
         "#{assigns.prefix}-service-line1"}
      end

    assigns =
      assigns
      |> assign(:line1_name, "#{assigns.prefix}[#{line1}]")
      |> assign(:line2_name, "#{assigns.prefix}[#{line2}]")
      |> assign(:city_name, "#{assigns.prefix}[#{city}]")
      |> assign(:state_name, "#{assigns.prefix}[#{state}]")
      |> assign(:postal_name, "#{assigns.prefix}[#{postal}]")
      |> assign(:line1_val, assigns.values[line1] || "")
      |> assign(:line2_val, assigns.values[line2] || "")
      |> assign(:city_val, assigns.values[city] || "")
      |> assign(:state_val, assigns.values[state] || "")
      |> assign(:postal_val, assigns.values[postal] || "")
      |> assign(:line1_id, line1_id)

    ~H"""
    <div class="space-y-2">
      <div>
        <label for={@line1_id} class="block text-xs font-medium text-base-content/70 mb-0.5">
          Address line 1
        </label>
        <input
          id={@line1_id}
          type="text"
          name={@line1_name}
          value={@line1_val}
          data-address-part={@part}
          data-address-field="line1"
          data-address-autocomplete
          autocomplete="address-line1"
          class="input input-bordered input-sm w-full"
        />
      </div>
      <div>
        <label class="block text-xs font-medium text-base-content/70 mb-0.5">Address line 2</label>
        <input
          type="text"
          name={@line2_name}
          value={@line2_val}
          data-address-part={@part}
          data-address-field="line2"
          autocomplete="address-line2"
          class="input input-bordered input-sm w-full"
        />
      </div>
      <div class="grid grid-cols-6 gap-2">
        <div class="col-span-3">
          <label class="block text-xs font-medium text-base-content/70 mb-0.5">City</label>
          <input
            type="text"
            name={@city_name}
            value={@city_val}
            data-address-part={@part}
            data-address-field="city"
            autocomplete="address-level2"
            class="input input-bordered input-sm w-full"
          />
        </div>
        <div class="col-span-1">
          <label class="block text-xs font-medium text-base-content/70 mb-0.5">State</label>
          <input
            type="text"
            name={@state_name}
            value={@state_val}
            data-address-part={@part}
            data-address-field="state"
            autocomplete="address-level1"
            maxlength="2"
            class="input input-bordered input-sm w-full uppercase"
          />
        </div>
        <div class="col-span-2">
          <label class="block text-xs font-medium text-base-content/70 mb-0.5">ZIP</label>
          <input
            type="text"
            name={@postal_name}
            value={@postal_val}
            data-address-part={@part}
            data-address-field="postal_code"
            autocomplete="postal-code"
            class="input input-bordered input-sm w-full"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :suggestion, :map, required: true
  attr :target, :any, default: nil

  defp address_suggestion_panel(assigns) do
    ~H"""
    <div class="rounded-md border border-base-300 bg-base-100 p-3 text-sm space-y-2">
      <p class="font-medium text-base-content">We found a standardized address. Which should we use?</p>
      <p class="text-base-content/80">
        <span class="font-medium">What you entered:</span> {@suggestion["typed_formatted"]}
      </p>
      <p class="text-base-content/80">
        <span class="font-medium">Suggested:</span> {@suggestion["suggested_formatted"]}
      </p>
      <div class="flex flex-wrap gap-2 pt-1">
        <button
          type="button"
          phx-click="address_apply_choice"
          phx-target={@target}
          phx-value-part={@suggestion["part"]}
          phx-value-choice="typed"
          class="btn btn-brand btn-xs"
        >
          Use what I entered
        </button>
        <button
          type="button"
          phx-click="address_apply_choice"
          phx-target={@target}
          phx-value-part={@suggestion["part"]}
          phx-value-choice="suggested"
          class="btn btn-brand-soft btn-xs"
        >
          Use suggested address
        </button>
      </div>
    </div>
    """
  end

  defp truthy?(v) when v in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_), do: false
end
