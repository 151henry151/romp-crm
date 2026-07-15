defmodule RompCrm.Bookings.CustomerSchedulingSmsTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.ApplicationConfig
  alias RompCrm.Bookings
  alias RompCrm.Bookings.{CustomerSchedulingSms, Orchestrator}
  alias RompCrm.SmsConversations

  setup do
    prev = Application.get_env(:romp_crm, :customer_scheduling_sms_enabled)

    on_exit(fn ->
      if is_nil(prev) do
        Application.delete_env(:romp_crm, :customer_scheduling_sms_enabled)
      else
        Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, prev)
      end
    end)

    :ok
  end

  test "customer_scheduling_sms_enabled?/0 reflects config" do
    Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, false)
    refute ApplicationConfig.customer_scheduling_sms_enabled?()
    refute CustomerSchedulingSms.enabled?()

    Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, true)
    assert ApplicationConfig.customer_scheduling_sms_enabled?()
    assert CustomerSchedulingSms.enabled?()
  end

  test "send_sms/2 skips Twilio when disabled" do
    Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, false)
    assert {:ok, :feature_disabled} = CustomerSchedulingSms.send_sms("+18025550100", "hello")
  end

  test "booking_initiate does not create a link or client thread when disabled" do
    Application.put_env(:romp_crm, :customer_scheduling_sms_enabled, false)

    user = user_fixture()
    business = business_fixture(%{owner_user: user, name: "Kill Switch Plumbing"})
    ctx = %{business_id: business.id, user_id: user.id, message_sid: "SMkill"}

    op =
      {:booking_initiate,
       %{
         client_id: nil,
         client_name: "Pat Pending",
         phone: "8025550199",
         job_id: nil,
         job_type_label: "drain clear",
         duration_min_minutes: 60,
         duration_max_minutes: 90
       }}

    assert {:ok, [{:skipped, :customer_scheduling_sms_disabled}]} =
             Orchestrator.run_operations([op], ctx)

    assert Bookings.active_links_for_client_phone("18025550199") == []
    assert SmsConversations.list_client_turns_for_ai(business.id, "18025550199") == []
  end
end
