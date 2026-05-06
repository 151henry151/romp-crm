defmodule JgsCrmWeb.TwilioWebhookControllerTest do
  use JgsCrmWeb.ConnCase

  import ExUnit.CaptureLog

  require Logger

  alias JgsCrm.Jobs

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  test "POST /webhooks/twilio/sms updates job when Body uses STUB_UPDATE JSON", %{conn: conn} do
    job =
      JgsCrm.JobsFixtures.job_fixture(%{
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

    assert log =~ "Twilio SMS inbound: sid=SMstubupdate from=+15555550123"
    assert log =~ "Twilio SMS parsed update: sid=SMstubupdate"
    assert log =~ "Twilio SMS update applied: sid=SMstubupdate"

    updated = Jobs.get_job!(job.id)
    assert updated.address == "42 Maple St, Burlington VT"
  end

  test "POST /webhooks/twilio/sms creates a job from SMS Body", %{conn: conn} do
    before = Jobs.list_jobs() |> length()

    conn =
      conn
      |> post(~p"/webhooks/twilio/sms", %{
        "Body" => "Customer John at 123 Main needs drain line repair urgent callback please",
        "From" => "+15555550123",
        "MessageSid" => "SMxxxxxxxx"
      })

    assert response(conn, 200) =~ "<Response>"
    assert Jobs.list_jobs() |> length() == before + 1

    assert Enum.any?(Jobs.list_jobs(), fn j ->
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
end
