defmodule JgsCrmWeb.Router do
  use JgsCrmWeb, :router

  import JgsCrmWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JgsCrmWeb.Layouts, :root}
    plug :protect_from_forgery_with_hosts
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # CSRF tokens may embed the request host; behind nginx allow apex + www so occasional
  # Host variance does not reject valid posts with "Forbidden".
  defp protect_from_forgery_with_hosts(conn, _opts),
    do: protect_from_forgery(conn, allow_hosts: ["hromp.com", "www.hromp.com"])

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Twilio sends POST form bodies; minimal pipeline without CSRF or session.
  pipeline :webhooks do
    plug :accepts, ["html"]
  end

  scope "/webhooks/twilio", JgsCrmWeb do
    pipe_through :webhooks

    post "/sms", TwilioWebhookController, :sms
  end

  if Application.compile_env(:jgs_crm, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: JgsCrmWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Redirect root to login if not authenticated
  scope "/", JgsCrmWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", JgsCrmWeb do
    pipe_through [:browser]

    get "/invitations/:token", InvitationController, :show

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Authenticated routes
  scope "/", JgsCrmWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    post "/business/switch", BusinessSwitchController, :update

    live_session :authenticated_business_pages,
      on_mount: [{JgsCrmWeb.UserAuth, :require_authenticated}] do
      live "/businesses", BusinessesLive, :index
    end

    live_session :authenticated_jobs,
      on_mount: [
        {JgsCrmWeb.UserAuth, :require_authenticated},
        {JgsCrmWeb.UserAuth, :ensure_business_scope}
      ] do
      live "/", JobsLive, :index
      live "/jobs/new", JobsLive, :new
      live "/jobs/:id/edit", JobsLive, :edit
    end
  end
end
