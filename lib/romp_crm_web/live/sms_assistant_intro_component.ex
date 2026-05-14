defmodule RompCrmWeb.SmsAssistantIntroComponent do
  @moduledoc false
  use RompCrmWeb, :live_component

  alias RompCrm.Accounts
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.take(assigns, [:id, :current_scope, :show]))

    user = assigns.current_scope.user

    socket =
      if is_nil(socket.assigns[:form]) do
        assign(
          socket,
          :form,
          to_form(Accounts.change_user_profile(user, %{}), as: :user_profile)
        )
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal
        id="sms-assistant-intro-modal"
        show={@show}
        on_cancel={JS.push("sms_intro_skip", target: @myself)}
      >
        <h2 id="sms-assistant-intro-modal-title" class="pr-8 text-lg font-semibold text-gray-900">
          Text your Romp CRM assistant
        </h2>
        <p class="mt-3 text-sm leading-relaxed text-gray-700">
          To create jobs, edit customer details, or look up any info from your job list, you can just text your AI assistant who manages your job list for you. If you’d rather enter things yourself, you can skip this feature, but it’s really what makes Romp CRM shine. Enter your phone number to get started.
        </p>
        <.form
          for={@form}
          id="sms-intro-form"
          phx-change="validate_intro_phone"
          phx-submit="save_intro_phone"
          phx-target={@myself}
          class="mt-5 space-y-4"
        >
          <.input field={@form[:phone]} type="tel" label="Phone number" autocomplete="tel" />
          <div class="flex flex-wrap justify-end gap-2 pt-1">
            <.button
              type="button"
              class="btn btn-ghost"
              phx-click="sms_intro_skip"
              phx-target={@myself}
            >
              Skip for now
            </.button>
            <.button type="submit" class="btn btn-primary">
              Save and text me
            </.button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("validate_intro_phone", %{"user_profile" => params}, socket) do
    user = socket.assigns.current_scope.user
    cs = Accounts.change_user_profile(user, params)
    {:noreply, assign(socket, :form, to_form(cs, as: :user_profile))}
  end

  def handle_event("save_intro_phone", %{"user_profile" => params}, socket) do
    user = socket.assigns.current_scope.user
    phone = params["phone"] |> to_string() |> String.trim()

    if phone == "" do
      cs =
        user
        |> Accounts.change_user_profile(%{"phone" => ""})
        |> Ecto.Changeset.add_error(:phone, "enter your number or tap Skip for now")

      {:noreply, assign(socket, :form, to_form(cs, as: :user_profile))}
    else
      case Accounts.complete_sms_assistant_intro_with_phone(user, params) do
        {:ok, user, sms_result} ->
          send(self(), {:sms_assistant_intro, :updated, user})
          {:noreply, socket |> put_flash_for_sms_result(sms_result)}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, :form, to_form(cs, as: :user_profile))}
      end
    end
  end

  def handle_event("sms_intro_skip", _params, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.skip_sms_assistant_intro(user) do
      {:ok, user} ->
        send(self(), {:sms_assistant_intro, :updated, user})

        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(
           :info,
           "You can add your mobile number anytime under Account Settings."
         )}

      {:error, _} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, "Could not save your choice. Try again.")}
    end
  end

  defp put_flash_for_sms_result(socket, sms_result) do
    case sms_result do
      {:ok, :skipped} ->
        Phoenix.LiveView.put_flash(
          socket,
          :info,
          "Saved your number. Outbound texts are off on this server, so no welcome SMS was sent."
        )

      {:ok, :no_e164} ->
        Phoenix.LiveView.put_flash(
          socket,
          :error,
          "That number could not be used for SMS. Fix the format or update it in Settings."
        )

      {:error, _} ->
        Phoenix.LiveView.put_flash(
          socket,
          :error,
          "Your number was saved, but sending the welcome text failed. You can try again from Settings."
        )

      {:ok, _} ->
        Phoenix.LiveView.put_flash(
          socket,
          :info,
          "Check your phone for a welcome message from Romp CRM."
        )

      _ ->
        Phoenix.LiveView.put_flash(socket, :info, "You're all set.")
    end
  end
end
