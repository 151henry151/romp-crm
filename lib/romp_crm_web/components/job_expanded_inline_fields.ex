defmodule RompCrmWeb.JobExpandedInlineFields do
  @moduledoc false
  use Phoenix.Component

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :variant, :atom, required: true

  def job_expanded_inline_fields(assigns) do
    wrap =
      cond do
        assigns.variant == :desktop -> "contents"
        true -> "space-y-2"
      end

    wide = if assigns.variant == :desktop, do: "lg:col-span-2", else: ""

    assigns =
      assigns
      |> assign(:wrap, wrap)
      |> assign(:wide, wide)

    ~H"""
    <div class={@wrap}>
      <%= if @can_edit_jobs do %>
        <.field_row variant={@variant} col="" label="Client">
          <input
            type="text"
            name={"job_#{@job.id}_client_name"}
            value={@job.client_name || ""}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="client_name"
            phx-debounce="400"
            class="input input-bordered input-sm w-full min-w-0"
          />
        </.field_row>
        <.field_row variant={@variant} col="" label="Address">
          <input
            type="text"
            name={"job_#{@job.id}_address"}
            value={@job.address || ""}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="address"
            phx-debounce="400"
            class="input input-bordered input-sm w-full min-w-0"
          />
        </.field_row>
        <.field_row variant={@variant} col="" label="Phone">
          <input
            type="text"
            name={"job_#{@job.id}_phone"}
            value={@job.phone || ""}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="phone"
            phx-debounce="400"
            class="input input-bordered input-sm w-full min-w-0"
          />
        </.field_row>
        <.field_row variant={@variant} col="" label="Priority">
          <select
            name={"job_#{@job.id}_priority"}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="priority"
            class="select select-bordered select-sm w-full min-w-0 max-w-xs"
          >
            <option value="normal" selected={@job.priority == :normal}>Normal</option>
            <option value="high" selected={@job.priority == :high}>High</option>
          </select>
        </.field_row>
        <.field_row variant={@variant} col="" label="Status">
          <select
            name={"job_#{@job.id}_status"}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="status"
            class="select select-bordered select-sm w-full min-w-0 max-w-xs"
          >
            <%= for {lab, val} <- [{"Lead", "lead"}, {"Pending", "pending"}, {"In Progress", "in_progress"}, {"Done", "done"}] do %>
              <option value={val} selected={to_string(@job.status) == val}>{lab}</option>
            <% end %>
          </select>
        </.field_row>
        <.field_row variant={@variant} col="" label="Referred by">
          <input
            type="text"
            name={"job_#{@job.id}_referred_by"}
            value={@job.referred_by || ""}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="referred_by"
            phx-debounce="400"
            class="input input-bordered input-sm w-full min-w-0"
          />
        </.field_row>
        <.field_row variant={@variant} col="" label="Next action">
          <input
            type="text"
            name={"job_#{@job.id}_next_action"}
            value={@job.next_action || ""}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="next_action"
            phx-debounce="400"
            class="input input-bordered input-sm w-full min-w-0"
          />
        </.field_row>
        <.field_row variant={@variant} col={@wide} label="Work description">
          <textarea
            name={"job_#{@job.id}_work_description"}
            rows="3"
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="work_description"
            phx-debounce="400"
            class="textarea textarea-bordered textarea-sm w-full min-w-0 text-sm"
          ><%= @job.work_description || "" %></textarea>
        </.field_row>
        <.field_row variant={@variant} col={@wide} label="Job scheduled (optional)">
          <input
            type="date"
            name={"job_#{@job.id}_scheduled_on"}
            value={@job.scheduled_on && Date.to_iso8601(@job.scheduled_on)}
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="scheduled_on"
            class="input input-bordered input-sm w-full min-w-0 max-w-[11rem]"
          />
        </.field_row>
        <.field_row variant={@variant} col={@wide} label="Notes">
          <textarea
            name={"job_#{@job.id}_notes"}
            rows="3"
            phx-change="inline_job_update"
            phx-value-job_id={@job.id}
            phx-value-field="notes"
            phx-debounce="400"
            class="textarea textarea-bordered textarea-sm w-full min-w-0 text-sm"
          ><%= @job.notes || "" %></textarea>
        </.field_row>
      <% else %>
        <p><span class="font-medium text-base-content/90">Client:</span> {@job.client_name}</p>
        <p><span class="font-medium text-base-content/90">Address:</span> {display(@job.address)}</p>
        <p><span class="font-medium text-base-content/90">Phone:</span> {display(@job.phone)}</p>
        <p>
          <span class="font-medium text-base-content/90">Priority:</span>
          <%= if @job.priority == :high, do: "High", else: "Normal" %>
        </p>
        <p><span class="font-medium text-base-content/90">Status:</span> {status_label(@job.status)}</p>
        <p><span class="font-medium text-base-content/90">Referred by:</span> {display(@job.referred_by)}</p>
        <p><span class="font-medium text-base-content/90">Next action:</span> {display(@job.next_action)}</p>
        <p class={@wide}>
          <span class="font-medium text-base-content/90">Work description:</span>
          <span class="mt-1 block whitespace-pre-wrap break-words text-base-content">{display(@job.work_description)}</span>
        </p>
        <%= if @job.scheduled_on do %>
          <p class={@wide}>
            <span class="font-medium text-base-content/90">Scheduled:</span>
            <span class="text-base-content">{Date.to_iso8601(@job.scheduled_on)}</span>
          </p>
        <% end %>
        <p class={@wide}>
          <span class="font-medium text-base-content/90">Notes:</span> {display(@job.notes)}
        </p>
      <% end %>
    </div>
    """
  end

  attr :variant, :atom, required: true
  attr :col, :string, default: ""
  attr :label, :string, required: true
  slot :inner_block, required: true

  def field_row(assigns) do
    ~H"""
    <div class={["min-w-0", @col]}>
      <label class="block text-xs font-medium text-base-content/70 mb-0.5">{@label}</label>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp display(nil), do: "—"
  defp display(""), do: "—"
  defp display(v), do: v

  defp status_label(:lead), do: "Lead"
  defp status_label(:pending), do: "Pending"
  defp status_label(:in_progress), do: "In Progress"
  defp status_label(:done), do: "Done"
end
