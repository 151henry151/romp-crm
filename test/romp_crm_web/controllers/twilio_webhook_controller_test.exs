defmodule RompCrmWeb.TwilioWebhookControllerTest do
  use RompCrmWeb.ConnCase

  import ExUnit.CaptureLog

  alias RompCrm.Accounts
  alias RompCrm.AccountsFixtures
  alias RompCrm.Businesses
  alias RompCrm.Jobs
  alias RompCrm.JobsFixtures
  alias RompCrm.Repo

  setup %{conn: conn} do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    user = AccountsFixtures.user_fixture()
    {:ok, business} = Businesses.create_business(user, %{name: "SMS Test Co"})
    {:ok, _} = Accounts.update_user_profile(user, %{phone: "+15555550123"})

    {:ok, conn: conn, sms_business: business}
  end

  test "POST /webhooks/twilio/sms updates job when Body uses STUB_UPDATE with job_id", %{
    conn: conn,
    sms_business: biz
  } do
    job =
      RompCrm.JobsFixtures.job_fixture(%{
        business_id: biz.id,
        client_name: "Angela Brande",
        address: nil,
        phone: nil
      })

    body =
      "STUB_UPDATE " <>
        Jason.encode!(%{
          "job_id" => job.id,
          "updates" => %{"address" => "42 Maple St, Burlington VT"}
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => body,
            "From" => "+15555550123",
            "MessageSid" => "SMstubupdatebyid"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "Agent inbound (sms): sid=SMstubupdatebyid"
    assert log =~ "job_id=#{job.id}"
    assert log =~ "Twilio SMS update applied: sid=SMstubupdatebyid"

    updated = Jobs.get_job!(job.id, biz.id)
    assert updated.address == "42 Maple St, Burlington VT"
  end

  test "POST /webhooks/twilio/sms updates job when Body uses STUB_UPDATE match fallback", %{
    conn: conn,
    sms_business: biz
  } do
    job =
      RompCrm.JobsFixtures.job_fixture(%{
        business_id: biz.id,
        client_name: "Angela Brande",
        address: nil,
        phone: nil
      })

    body =
      "STUB_UPDATE " <>
        Jason.encode!(%{
          "match" => %{"client_name" => "Angela Brande"},
          "updates" => %{"address" => "42 Maple St, Burlington VT"}
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => body,
            "From" => "+15555550123",
            "MessageSid" => "SMstubupdate"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "Agent inbound (sms): sid=SMstubupdate"
    assert log =~ "from=+15555550123"
    assert log =~ "match="
    assert log =~ "Twilio SMS parsed update: sid=SMstubupdate"
    assert log =~ "Twilio SMS update applied: sid=SMstubupdate"

    updated = Jobs.get_job!(job.id, biz.id)
    assert updated.address == "42 Maple St, Burlington VT"
  end

  test "POST /webhooks/twilio/sms creates a job from SMS Body", %{conn: conn, sms_business: biz} do
    before = Jobs.list_jobs(biz.id) |> length()

    conn =
      conn
      |> post(~p"/webhooks/twilio/sms", %{
        "Body" => "Customer John at 123 Main needs drain line repair urgent callback please",
        "From" => "+15555550123",
        "MessageSid" => "SMxxxxxxxx"
      })

    assert response(conn, 200) =~ "<Response>"
    assert Jobs.list_jobs(biz.id) |> length() == before + 1

    assert Enum.any?(Jobs.list_jobs(biz.id), fn j ->
             j.client_name == "Test SMS Lead" and
               String.contains?(j.work_description || "", "Customer John")
           end)
  end

  test "POST /webhooks/twilio/sms logs no-match update path", %{conn: conn} do
    body =
      "STUB_UPDATE " <>
        Jason.encode!(%{
          "match" => %{"client_name" => "No Such Customer 999"},
          "updates" => %{"address" => "123 Unknown Rd"}
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => body,
            "From" => "+15555550123",
            "MessageSid" => "SMnomatch"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "Twilio SMS parsed update: sid=SMnomatch"
    assert log =~ "Twilio SMS update skipped: sid=SMnomatch"
    assert log =~ "reason=:no_match"
  end

  test "POST /webhooks/twilio/sms skips update when STUB job_id not in snapshot", %{
    conn: conn,
    sms_business: biz
  } do
    _job = RompCrm.JobsFixtures.job_fixture(%{business_id: biz.id, client_name: "Someone"})

    body =
      "STUB_UPDATE " <>
        Jason.encode!(%{
          "job_id" => 999_999,
          "updates" => %{"address" => "Nowhere Rd"}
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => body,
            "From" => "+15555550123",
            "MessageSid" => "SMbadid"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "Twilio SMS parsed update: sid=SMbadid"
    assert log =~ "reason=:invalid_job_id"
  end

  test "POST /webhooks/twilio/sms ignores CRM when From does not match any user profile phone", %{
    conn: conn,
    sms_business: biz
  } do
    before = Jobs.list_jobs(biz.id) |> length()

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => "Customer John at 123 Main needs drain line repair urgent callback please",
            "From" => "+19998887777",
            "MessageSid" => "SMnotallowed"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "no user with profile phone matching"
    refute log =~ "Agent inbound (sms): sid=SMnotallowed"
    assert Jobs.list_jobs(biz.id) |> length() == before
  end

  test "POST /webhooks/twilio/sms applies multiple create/update operations from one message", %{
    conn: conn,
    sms_business: biz
  } do
    existing =
      RompCrm.JobsFixtures.job_fixture(%{
        business_id: biz.id,
        client_name: "Toilet Customer",
        work_description: "Toilet replacement",
        phone: nil
      })

    before = Jobs.list_jobs(biz.id) |> length()

    body =
      "STUB_JSON " <>
        Jason.encode!(%{
          "actions" => [
            %{
              "intent" => "create",
              "job" => %{
                "client_name" => "Mark Sino",
                "work_description" => "Replace refrigerator"
              }
            },
            %{
              "intent" => "create",
              "job" => %{
                "client_name" => "Dave Woll",
                "work_description" => "Clogged drain"
              }
            },
            %{
              "intent" => "update",
              "job_id" => existing.id,
              "updates" => %{"phone" => "8029897658"}
            }
          ]
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => body,
            "From" => "+15555550123",
            "MessageSid" => "SMbatch"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "Twilio SMS parsed operations: sid=SMbatch"
    assert log =~ "count=3"
    assert log =~ "op_index=1"
    assert log =~ "op_index=2"
    assert log =~ "op_index=3"

    assert Jobs.list_jobs(biz.id) |> length() == before + 2
    assert Jobs.get_job!(existing.id, biz.id).phone == "8029897658"

    assert Enum.any?(Jobs.list_jobs(biz.id), fn j ->
             j.client_name == "Mark Sino" and j.work_description == "Replace refrigerator"
           end)

    assert Enum.any?(Jobs.list_jobs(biz.id), fn j ->
             j.client_name == "Dave Woll" and j.work_description == "Clogged drain"
           end)
  end

  test "POST /webhooks/twilio/sms targets Jobs picker workspace, not Settings SMS default alone",
       %{
         conn: conn
       } do
    user = AccountsFixtures.user_fixture()
    {:ok, biz_a} = Businesses.create_business(user, %{name: "Default SMS Org"})
    {:ok, biz_b} = Businesses.create_business(user, %{name: "Picker Org"})
    {:ok, _} = Accounts.update_user_profile(user, %{phone: "+15555550999"})

    job =
      JobsFixtures.job_fixture(%{
        business_id: biz_b.id,
        client_name: "Picker-only client",
        address: nil
      })

    {:ok, _} =
      Accounts.get_user!(user.id)
      |> Ecto.Changeset.change(sms_business_id: biz_a.id)
      |> Repo.update()

    assert {:ok, _} = Accounts.put_jobs_workspace_selection(Accounts.get_user!(user.id), biz_b.id)

    body =
      "STUB_UPDATE " <>
        Jason.encode!(%{
          "job_id" => job.id,
          "updates" => %{"address" => "Via picker routing"}
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          conn
          |> post(~p"/webhooks/twilio/sms", %{
            "Body" => body,
            "From" => "+15555550999",
            "MessageSid" => "SMpickerworkspace"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "business_id=#{biz_b.id}"
    assert log =~ "Twilio SMS update applied: sid=SMpickerworkspace"
    assert Jobs.get_job!(job.id, biz_b.id).address == "Via picker routing"
  end

  test "POST /webhooks/twilio/sms stores proposed creates until CONFIRM", %{
    conn: conn,
    sms_business: biz
  } do
    propose_body =
      "STUB_PROPOSE " <>
        Jason.encode!(%{
          "assistant_sms" =>
            "I read a text from Jimmy Wang. Reply CONFIRM to create this lead.",
          "image_kind" => "sms_screenshot",
          "proposed_job_creates" => [
            %{
              "job" => %{
                "client_name" => "Jimmy Wang",
                "address" => "123 Bonehead Drive",
                "work_description" => "Leaking sink faucet",
                "status" => "lead"
              },
              "attach_media_urls" => []
            }
          ],
          "job_actions" => [],
          "time_actions" => [],
          "employee_actions" => [],
          "reminder_actions" => []
        })

    log =
      capture_log([level: :info], fn ->
        conn =
          post(conn, ~p"/webhooks/twilio/sms", %{
            "Body" => propose_body,
            "From" => "+15555550123",
            "MessageSid" => "SMstubpropose1"
          })

        assert response(conn, 200) =~ "<Response>"
      end)

    assert log =~ "proposed job creates"
    refute Jobs.list_jobs(biz.id) |> Enum.any?(&(&1.client_name == "Jimmy Wang"))

    capture_log([level: :info], fn ->
      conn =
        build_conn()
        |> post(~p"/webhooks/twilio/sms", %{
          "Body" => "confirm",
          "From" => "+15555550123",
          "MessageSid" => "SMstubconfirm1"
        })

      assert response(conn, 200) =~ "<Response>"
    end)

    assert Jobs.list_jobs(biz.id) |> Enum.any?(&(&1.client_name == "Jimmy Wang"))
  end

  test "POST /webhooks/twilio/voice returns TwiML Dial to configured forward number", %{
    conn: conn
  } do
    conn =
      post(conn, ~p"/webhooks/twilio/voice", %{
        "CallSid" => "CAtestvoice01",
        "From" => "+15555550123",
        "To" => "+18022780965"
      })

    body = response(conn, 200)
    assert body =~ "<Dial"
    assert body =~ "+18024587299"
    assert get_resp_header(conn, "content-type") |> hd() =~ "xml"
  end
end
