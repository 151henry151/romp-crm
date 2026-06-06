defmodule RompCrmWeb.ClientExpandedInlineFields do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1]
  import RompCrmWeb.AddressFieldsComponent, only: [address_fields: 1]
  import RompCrmWeb.PhoneFieldComponent, only: [phone_field: 1]

  alias RompCrmWeb.ClientExpandEditKeys, as: EK
  alias RompCrmWeb.AddressValues
  alias RompCrm.Addresses
  alias RompCrm.Clients.Client
  alias RompCrm.ContactInfo

  attr :client, Client, required: true
  attr :can_edit, :boolean, default: false
  attr :edit_keys, :any, required: true
  attr :address_suggestion, :map, default: nil

  def client_expanded_inline_fields(assigns) do
    ~H"""
    <div class="space-y-2 min-w-0">
      <%= if @can_edit do %>
        <.client_field label="Client" editing?={editing?(@edit_keys, EK.client(@client.id, "client_name"))} edit_key={EK.client(@client.id, "client_name")} client_id={@client.id} field="client_name">
          <:readonly>{@client.client_name || "—"}</:readonly>
          <:editor><input type="text" name="value" value={@client.client_name || ""} class="input input-bordered input-sm w-full min-w-0" /></:editor>
        </.client_field>
        <.client_field label="Address" editing?={editing?(@edit_keys, EK.client(@client.id, "address"))} edit_key={EK.client(@client.id, "address")} client_id={@client.id} field="address" submit_event="client_expand_commit_address">
          <:readonly>
            <div class="space-y-1">
              <p>{Addresses.format_service(@client)}</p>
              <%= if @client.billing_address_different do %>
                <p class="text-xs text-base-content/70">Billing: {Addresses.format_billing(@client)}</p>
              <% end %>
            </div>
          </:readonly>
          <:editor>
            <.address_fields id={"client-#{@client.id}-address"} name_prefix="client" values={AddressValues.from_client(@client)} suggestion={@address_suggestion} />
          </:editor>
        </.client_field>
        <.client_field label="Phone" editing?={editing?(@edit_keys, EK.client(@client.id, "phone"))} edit_key={EK.client(@client.id, "phone")} client_id={@client.id} field="phone">
          <:readonly>{display_phone(@client.phone)}</:readonly>
          <:editor><.phone_field id={"client-#{@client.id}-phone"} name="value" value={@client.phone} class="input input-bordered input-sm" select_class="select select-bordered select-sm" /></:editor>
        </.client_field>
        <.client_field label="Email" editing?={editing?(@edit_keys, EK.client(@client.id, "client_email"))} edit_key={EK.client(@client.id, "client_email")} client_id={@client.id} field="client_email">
          <:readonly>{display(@client.client_email)}</:readonly>
          <:editor><input type="email" name="value" value={@client.client_email || ""} pattern={ContactInfo.email_html_pattern()} title={ContactInfo.email_hint()} class="input input-bordered input-sm w-full min-w-0" /></:editor>
        </.client_field>
        <.client_field label="Notes" editing?={editing?(@edit_keys, EK.client(@client.id, "notes"))} edit_key={EK.client(@client.id, "notes")} client_id={@client.id} field="notes">
          <:readonly><span class="whitespace-pre-wrap break-words">{display(@client.notes)}</span></:readonly>
          <:editor><textarea name="value" rows="3" class="textarea textarea-bordered textarea-sm w-full min-w-0 text-sm"><%= @client.notes || "" %></textarea></:editor>
        </.client_field>
      <% else %>
        <p><span class="font-medium text-base-content/90">Client:</span> {@client.client_name}</p>
        <p><span class="font-medium text-base-content/90">Address:</span> {Addresses.format_service(@client)}</p>
        <p><span class="font-medium text-base-content/90">Phone:</span> {display_phone(@client.phone)}</p>
        <p><span class="font-medium text-base-content/90">Email:</span> {display(@client.client_email)}</p>
        <p><span class="font-medium text-base-content/90">Notes:</span> {display(@client.notes)}</p>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :editing?, :boolean, required: true
  attr :edit_key, :string, required: true
  attr :client_id, :integer, required: true
  attr :field, :string, required: true
  attr :submit_event, :string, default: "client_expand_commit"
  slot :readonly, required: true
  slot :editor, required: true

  def client_field(assigns) do
    ~H"""
    <div class="min-w-0">
      <span class="block text-xs font-medium text-base-content/70 mb-0.5">{@label}</span>
      <%= if @editing? do %>
        <form phx-submit={@submit_event} class="flex flex-wrap items-end gap-1.5 min-w-0">
          <input type="hidden" name="client_id" value={@client_id} />
          <%= if @submit_event == "client_expand_commit" do %>
            <input type="hidden" name="field" value={@field} />
          <% end %>
          <div class="min-w-0 flex-1 basis-[min(100%,18rem)]">{render_slot(@editor)}</div>
          <div class="flex shrink-0 items-center gap-0.5">
            <button type="submit" class="btn btn-square btn-ghost btn-xs h-8 w-8 text-green-600 hover:bg-green-500/15" aria-label={"Save #{@label}"}><.icon name="hero-check" class="size-4" /></button>
            <button type="button" phx-click="client_expand_edit_cancel" phx-value-key={@edit_key} class="btn btn-square btn-ghost btn-xs h-8 w-8 text-base-content/50" aria-label="Cancel"><.icon name="hero-x-mark" class="size-4" /></button>
          </div>
        </form>
      <% else %>
        <div class="flex items-start gap-1 min-w-0">
          <div class="min-w-0 flex-1 text-sm text-base-content">{render_slot(@readonly)}</div>
          <button type="button" phx-click="client_expand_edit_start" phx-value-key={@edit_key} class="btn btn-square btn-ghost btn-xs h-8 w-8 shrink-0 text-green-600 hover:bg-green-500/15" aria-label={"Edit #{@label}"}><.icon name="hero-pencil-square" class="size-4" /></button>
        </div>
      <% end %>
    </div>
    """
  end

  defp editing?(keys, key) when is_struct(keys, MapSet), do: MapSet.member?(keys, key)
  defp editing?(_, _), do: false
  defp display(nil), do: "—"
  defp display(""), do: "—"
  defp display(v), do: v
  defp display_phone(nil), do: "—"
  defp display_phone(""), do: "—"
  defp display_phone(phone), do: ContactInfo.format_display(phone)
end
