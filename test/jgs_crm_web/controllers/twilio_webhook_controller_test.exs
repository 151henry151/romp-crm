defmodule JgsCrmWeb.TwilioWebhookControllerTest do
  use JgsCrmWeb.ConnCase

  alias JgsCrm.Jobs

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
