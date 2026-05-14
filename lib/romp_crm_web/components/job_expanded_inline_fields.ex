defmodule RompCrmWeb.JobExpandedInlineFields do
  @moduledoc false
  use Phoenix.Component

  import RompCrmWeb.CoreComponents, only: [icon: 1]

  alias RompCrm.Jobs
  alias RompCrmWeb.JobExpandEditKeys, as: EK

  attr :job, :any, required: true
  attr :can_edit_jobs, :boolean, default: false
  attr :variant, :atom, required: true
  attr :edit_keys, :any, required: true

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
        <.job_field
          variant={@variant}
          col=""
          label="Client"
          editing?={editing?(@edit_keys, EK.job(@job.id, "client_name"))}
          edit_key={EK.job(@job.id, "client_name")}
          job_id={@job.id}
          field="client_name"
        >
          <:readonly>{@job.client_name || "—"}</:readonly>
          <:editor>
            <input type="text" name="value" value={@job.client_name || ""} class="input input-bordered input-sm w-full min-w-0" />
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col=""
          label="Address"
          editing?={editing?(@edit_keys, EK.job(@job.id, "address"))}
          edit_key={EK.job(@job.id, "address")}
          job_id={@job.id}
          field="address"
        >
          <:readonly>{display(@job.address)}</:readonly>
          <:editor>
            <input type="text" name="value" value={@job.address || ""} class="input input-bordered input-sm w-full min-w-0" />
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col=""
          label="Phone"
          editing?={editing?(@edit_keys, EK.job(@job.id, "phone"))}
          edit_key={EK.job(@job.id, "phone")}
          job_id={@job.id}
          field="phone"
        >
          <:readonly>{display(@job.phone)}</:readonly>
          <:editor>
            <input type="text" name="value" value={@job.phone || ""} class="input input-bordered input-sm w-full min-w-0" />
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col=""
          label="Priority"
          editing?={editing?(@edit_keys, EK.job(@job.id, "priority"))}
          edit_key={EK.job(@job.id, "priority")}
          job_id={@job.id}
          field="priority"
        >
          <:readonly>
            <%= if @job.priority == :high, do: "High", else: "Normal" %>
          </:readonly>
          <:editor>
            <select name="value" class="select select-bordered select-sm w-full min-w-0 max-w-xs">
              <option value="normal" selected={@job.priority == :normal}>Normal</option>
              <option value="high" selected={@job.priority == :high}>High</option>
            </select>
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col=""
          label="Status"
          editing?={editing?(@edit_keys, EK.job(@job.id, "status"))}
          edit_key={EK.job(@job.id, "status")}
          job_id={@job.id}
          field="status"
        >
          <:readonly>{status_label(@job.status)}</:readonly>
          <:editor>
            <select name="value" class="select select-bordered select-sm w-full min-w-0 max-w-xs">
              <%= for {lab, val} <- [{"Lead", "lead"}, {"Pending", "pending"}, {"In Progress", "in_progress"}, {"Done", "done"}] do %>
                <option value={val} selected={to_string(@job.status) == val}>{lab}</option>
              <% end %>
            </select>
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col=""
          label="Referred by"
          editing?={editing?(@edit_keys, EK.job(@job.id, "referred_by"))}
          edit_key={EK.job(@job.id, "referred_by")}
          job_id={@job.id}
          field="referred_by"
        >
          <:readonly>{display(@job.referred_by)}</:readonly>
          <:editor>
            <input type="text" name="value" value={@job.referred_by || ""} class="input input-bordered input-sm w-full min-w-0" />
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col=""
          label="Next action"
          editing?={editing?(@edit_keys, EK.job(@job.id, "next_action"))}
          edit_key={EK.job(@job.id, "next_action")}
          job_id={@job.id}
          field="next_action"
        >
          <:readonly>{display(@job.next_action)}</:readonly>
          <:editor>
            <input type="text" name="value" value={@job.next_action || ""} class="input input-bordered input-sm w-full min-w-0" />
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col={@wide}
          label="Work description"
          editing?={editing?(@edit_keys, EK.job(@job.id, "work_description"))}
          edit_key={EK.job(@job.id, "work_description")}
          job_id={@job.id}
          field="work_description"
        >
          <:readonly>
            <span class="whitespace-pre-wrap break-words text-base-content">{display(@job.work_description)}</span>
          </:readonly>
          <:editor>
            <textarea name="value" rows="3" class="textarea textarea-bordered textarea-sm w-full min-w-0 text-sm"><%= @job.work_description || "" %></textarea>
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col={@wide}
          label="Job scheduled (optional)"
          editing?={editing?(@edit_keys, EK.job(@job.id, "scheduled_on"))}
          edit_key={EK.job(@job.id, "scheduled_on")}
          job_id={@job.id}
          field="scheduled_on"
        >
          <:readonly>
            {Jobs.format_schedule_date_time(@job.scheduled_on, @job.scheduled_time) || "—"}
          </:readonly>
          <:editor>
            <div class="flex flex-wrap items-center gap-1.5 min-w-0">
              <input
                type="date"
                name="value"
                value={@job.scheduled_on && Date.to_iso8601(@job.scheduled_on)}
                class="input input-bordered input-sm w-[10.5rem] shrink-0 px-1 text-[11px] tabular-nums"
              />
              <input
                type="time"
                name="scheduled_time"
                value={format_time_input_value(@job.scheduled_time)}
                class="input input-bordered input-sm w-[6.25rem] shrink-0 px-1 text-[11px] tabular-nums"
                title="Optional time"
              />
            </div>
          </:editor>
        </.job_field>
        <.job_field
          variant={@variant}
          col={@wide}
          label="Notes"
          editing?={editing?(@edit_keys, EK.job(@job.id, "notes"))}
          edit_key={EK.job(@job.id, "notes")}
          job_id={@job.id}
          field="notes"
        >
          <:readonly>
            <span class="whitespace-pre-wrap break-words text-base-content">{display(@job.notes)}</span>
          </:readonly>
          <:editor>
            <textarea name="value" rows="3" class="textarea textarea-bordered textarea-sm w-full min-w-0 text-sm"><%= @job.notes || "" %></textarea>
          </:editor>
        </.job_field>
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
            <span class="text-base-content">{Jobs.format_schedule_date_time(@job.scheduled_on, @job.scheduled_time)}</span>
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
  attr :editing?, :boolean, required: true
  attr :edit_key, :string, required: true
  attr :job_id, :integer, required: true
  attr :field, :string, required: true
  slot :readonly, required: true
  slot :editor, required: true

  def job_field(assigns) do
    ~H"""
    <div class={["min-w-0", @col]}>
      <div class="flex items-center justify-between gap-1 mb-0.5">
        <span class="block text-xs font-medium text-base-content/70">{@label}</span>
      </div>
      <%= if @editing? do %>
        <form phx-submit="job_expand_commit_job" class="flex flex-wrap items-end gap-1.5 min-w-0">
          <input type="hidden" name="job_id" value={@job_id} />
          <input type="hidden" name="field" value={@field} />
          <div class="min-w-0 flex-1 basis-[min(100%,18rem)]">
            {render_slot(@editor)}
          </div>
          <button
            type="submit"
            class="btn btn-square btn-ghost btn-xs h-8 w-8 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
            aria-label={"Save #{@label}"}
          >
            <.icon name="hero-check" class="size-4" />
          </button>
          <button
            type="button"
            phx-click="job_expand_edit_cancel"
            phx-value-key={@edit_key}
            class="btn btn-square btn-ghost btn-xs h-8 w-8 min-h-0 shrink-0 text-base-content/50 hover:bg-base-300/40"
            aria-label={"Cancel editing #{@label}"}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </form>
      <% else %>
        <div class="flex items-start gap-1 min-w-0">
          <div class="min-w-0 flex-1 text-sm text-base-content">{render_slot(@readonly)}</div>
          <button
            type="button"
            phx-click="job_expand_edit_start"
            phx-value-key={@edit_key}
            class="btn btn-square btn-ghost btn-xs h-8 w-8 min-h-0 shrink-0 text-green-600 hover:bg-green-500/15"
            aria-label={"Edit #{@label}"}
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
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

  defp status_label(:lead), do: "Lead"
  defp status_label(:pending), do: "Pending"
  defp status_label(:in_progress), do: "In Progress"
  defp status_label(:done), do: "Done"

  defp format_time_input_value(%Time{} = t) do
    h = t.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    m = t.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    h <> ":" <> m
  end

  defp format_time_input_value(_), do: ""
end
