defmodule RompCrm.SmsMmsTest do
  use RompCrm.DataCase

  alias RompCrm.SmsConversations
  alias RompCrm.SmsMms

  test "body_for_storage includes MMS URLs when Body is empty" do
    params = %{
      "Body" => "",
      "NumMedia" => "1",
      "MediaUrl0" => "https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME123"
    }

    body = SmsMms.body_for_storage("", params)

    assert body =~ "Inbound SMS body empty"
    assert body =~ "api.twilio.com"
    assert String.trim(body) != ""
  end

  test "record_exchange accepts MMS storage body" do
    user = RompCrm.AccountsFixtures.user_fixture()
    {:ok, business} = RompCrm.Businesses.create_business(user, %{name: "MMS Biz"})

    assert {:ok, :ok} =
             SmsConversations.record_exchange(
               business.id,
               user.id,
               "15555550123",
               SmsMms.body_for_storage("", %{
                 "NumMedia" => "1",
                 "MediaUrl0" => "https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME123"
               }),
               "Saved your photo."
             )
  end

  test "extract_twilio_media_urls finds URLs in stored conversation text" do
    text = """
    (Inbound SMS body empty.)

    [MMS attachments — 1 URL(s) stored for follow-up:]
    1. https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME456
    """

    assert ["https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME456"] ==
             SmsMms.extract_twilio_media_urls(text)
  end

  test "orphan attach skips photo-only MMS even when older texts mention a client" do
    user = RompCrm.AccountsFixtures.user_fixture()
    {:ok, business} = RompCrm.Businesses.create_business(user, %{name: "MMS Biz"})
    phone = "18024587299"

    assert {:ok, :ok} =
             SmsConversations.record_exchange(
               business.id,
               user.id,
               phone,
               "Mary Frank dishwasher follow-up",
               "Got it."
             )

    jobs_snapshot = [%{"id" => 86, "client_name" => "Mary Frank"}]

    params = %{
      "NumMedia" => "1",
      "MediaUrl0" => "https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME789"
    }

    assert :skip ==
             SmsMms.maybe_attach_orphan_mms(
               [],
               business.id,
               phone,
               "",
               params,
               jobs_snapshot
             )
  end

  test "orphan attach with caption targets matching job when job exists" do
    user = RompCrm.AccountsFixtures.user_fixture()
    {:ok, business} = RompCrm.Businesses.create_business(user, %{name: "MMS Biz 2"})
    phone = "18024587298"

    {:ok, job} =
      RompCrm.Jobs.create_job(%{
        "business_id" => business.id,
        "client_name" => "Mary Frank",
        "status" => "pending"
      })

    jobs_snapshot = [%{"id" => job.id, "client_name" => "Mary Frank"}]

    params = %{
      "NumMedia" => "1",
      "MediaUrl0" => "https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME999"
    }

    # Attempts download (fails in test without Twilio creds) — proves we did not skip at inference.
    assert {:error, _} =
             SmsMms.maybe_attach_orphan_mms(
               [],
               business.id,
               phone,
               "For Mary Frank's dishwasher",
               params,
               jobs_snapshot
             )
  end
end
