defmodule JgsCrmWeb.TwilioWebhookControllerTest do
  use JgsCrmWeb.ConnCase

  alias JgsCrm.Jobs

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

    conn =
      conn
      |> post(~p"/webhooks/twilio/sms", %{
        "Body" => body,
        "From" => "+15555550123",
        "MessageSid" => "SMstubupdate"
      })

    assert response(conn, 200) =~ "<Response>"
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
end
