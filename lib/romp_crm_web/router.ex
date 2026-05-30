defmodule RompCrmWeb.Router do
  use RompCrmWeb, :router

  import RompCrmWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RompCrmWeb.Layouts, :root}
    plug :protect_from_forgery_with_hosts
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # CSRF tokens may embed the request host; behind nginx allow apex + www so occasional
  # Host variance does not reject valid posts with "Forbidden".
  defp protect_from_forgery_with_hosts(conn, _opts),
    do:
      protect_from_forgery(conn,
        allow_hosts: [
          "hromp.com",
          "www.hromp.com",
          "rompcrm.com",
          "www.rompcrm.com"
        ]
      )

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Twilio sends POST form bodies; minimal pipeline without CSRF or session.
  pipeline :webhooks do
    plug :accepts, ["json", "html"]
  end

  pipeline :redirect_logged_in_visitor do
    plug :redirect_if_user_is_authenticated
  end

  pipeline :require_logged_in_user do
    plug :require_authenticated_user
  end

  pipeline :require_paid_subscription do
    plug :require_active_subscription_user
  end

  scope "/webhooks/twilio", RompCrmWeb do
    pipe_through :webhooks

    post "/sms", TwilioWebhookController, :sms
    post "/voice", TwilioWebhookController, :voice
    get "/voice", TwilioWebhookController, :voice
  end

  scope "/webhooks/paypal", RompCrmWeb do
    pipe_through :webhooks

    post "/", PaypalWebhookController, :event
  end

  if Application.compile_env(:romp_crm, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: RompCrmWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Redirect root to login if not authenticated
  scope "/", RompCrmWeb do
    pipe_through [:browser, :redirect_logged_in_visitor]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", RompCrmWeb do
    pipe_through [:browser]

    get "/subscribe", SubscribeController, :show
    post "/subscribe/resume", SubscribeController, :resume
    get "/subscribe/paypal/return", SubscribeController, :paypal_return
    get "/subscribe/paypal/cancel", SubscribeController, :paypal_cancel

    get "/gift/redeem/:token", GiftRedeemController, :redirect_claim
    get "/gift/claim/:token", GiftRedeemController, :claim

    get "/invitations/:token", InvitationController, :show

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", RompCrmWeb do
    pipe_through [:browser, :require_logged_in_user]

    post "/gift/redeem/:token", GiftRedeemController, :create
  end

  scope "/", RompCrmWeb do
    pipe_through [:browser, :require_logged_in_user]

    live_session :admin,
      on_mount: [
        {RompCrmWeb.UserAuth, :require_authenticated},
        {RompCrmWeb.UserAuth, :require_admin}
      ] do
      live "/admin", AdminLive, :index
    end
  end

  # Authenticated routes
  scope "/", RompCrmWeb do
    pipe_through [:browser, :require_logged_in_user, :require_paid_subscription]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    post "/business/switch", BusinessSwitchController, :update

    post "/jobs/:job_id/photos", JobPhotoController, :create
    get "/jobs/:job_id/photos/download", JobPhotoController, :download_all
    get "/jobs/:job_id/photos/:photo_id/download", JobPhotoController, :download

    live_session :authenticated_business_pages,
      on_mount: [
        {RompCrmWeb.UserAuth, :require_authenticated},
        {RompCrmWeb.UserAuth, :require_active_subscription},
        {RompCrmWeb.UserAuth, :assign_sms_assistant_intro}
      ] do
      live "/businesses", BusinessesLive, :index
    end

    live_session :authenticated_support,
      on_mount: [
        {RompCrmWeb.UserAuth, :require_authenticated},
        {RompCrmWeb.UserAuth, :require_active_subscription},
        {RompCrmWeb.UserAuth, :assign_sms_assistant_intro}
      ] do
      live "/support", SupportLive, :index
    end

    live_session :authenticated_jobs,
      on_mount: [
        {RompCrmWeb.UserAuth, :require_authenticated},
        {RompCrmWeb.UserAuth, :require_active_subscription},
        {RompCrmWeb.UserAuth, :assign_sms_assistant_intro},
        {RompCrmWeb.UserAuth, :ensure_business_scope}
      ] do
      live "/", JobsLive, :index
      live "/jobs/new", JobsLive, :new
      live "/jobs/:id/edit", JobsLive, :edit

      live "/time-log", TimeLogLive, :index
      live "/my-timeclock", MyTimeclockLive, :index
      live "/reminders", RemindersLive, :index
      live "/chat", AgentChatLive, :index
    end

    live_session :authenticated_employees_owner,
      on_mount: [
        {RompCrmWeb.UserAuth, :require_authenticated},
        {RompCrmWeb.UserAuth, :require_active_subscription},
        {RompCrmWeb.UserAuth, :assign_sms_assistant_intro},
        {RompCrmWeb.UserAuth, :ensure_business_scope},
        {RompCrmWeb.UserAuth, :require_business_owner}
      ] do
      live "/employees", EmployeesLive, :index
      live "/employees/new", EmployeesLive, :new
      live "/employees/:id/edit", EmployeesLive, :edit
      live "/employees/:id", EmployeeDetailLive, :show
    end
  end
end
