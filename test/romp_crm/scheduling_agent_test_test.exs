defmodule RompCrm.SchedulingAgentTestTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.SchedulingAgentTest
  alias RompCrm.SchedulingAgentTest.Sandbox

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  setup do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business}
  end

  test "fresh session has welcome message and empty client pane", %{user: user, business: business} do
    state = SchedulingAgentTest.get_or_create_session(user, business.id)

    assert length(state["contractor_turns"]) == 1
    assert state["client_turns"] == []
    assert String.contains?(hd(state["contractor_turns"])["text"], "test workspace")
  end

  test "contractor STUB_JSON create + booking initiate shows client outreach", %{
    user: user,
    business: business
  } do
    json =
      Jason.encode!(%{
        "assistant_sms" => "I'll reach out to Sally.",
        "booking_actions" => [
          %{
            "intent" => "initiate",
            "client_name" => "Sally Pendleton",
            "phone" => "8025551234",
            "job_type_label" => "sink repair",
            "duration_min_minutes" => 90,
            "duration_max_minutes" => 120
          }
        ]
      })

    assert {:ok, _} =
             SchedulingAgentTest.send_contractor(user, business.id, "STUB_JSON #{json}")

    state = SchedulingAgentTest.get_or_create_session(user, business.id)
    assert length(state["booking_links"]) == 1
    assert length(state["clients"]) == 1
    assert length(state["client_turns"]) == 1
    assert hd(state["client_turns"])["role"] == "scheduling_assistant"
    assert String.contains?(hd(state["client_turns"])["text"], "scheduling assistant")
  end

  test "pending booking proposal then YES sends client SMS in sandbox", %{
    user: user,
    business: business
  } do
    create_json =
      Jason.encode!(%{
        "assistant_sms" => "Added Sally as a lead.",
        "job_actions" => [
          %{
            "intent" => "create",
            "job" => %{
              "client_name" => "Sally Pendleton",
              "phone" => "8025551234",
              "work_description" => "sink repair",
              "status" => "lead",
              "priority" => "normal"
            }
          }
        ],
        "proposed_booking_initiates" => [
          %{
            "client_name" => "Sally Pendleton",
            "phone" => "8025551234",
            "job_type_label" => "sink repair",
            "duration_min_minutes" => 90,
            "duration_max_minutes" => 120
          }
        ]
      })

    assert {:ok, _} =
             SchedulingAgentTest.send_contractor(user, business.id, "STUB_JSON #{create_json}")

    state = SchedulingAgentTest.get_or_create_session(user, business.id)
    assert state["pending_booking_proposal"] != nil
    assert state["client_turns"] == []

    assert {:ok, _} = SchedulingAgentTest.send_contractor(user, business.id, "YES")

    state = SchedulingAgentTest.get_or_create_session(user, business.id)
    assert state["pending_booking_proposal"] == nil
    assert length(state["client_turns"]) == 1
  end

  test "client STUB_CLARIFY reply in sandbox", %{user: user, business: business} do
    {:ok, state, _link, _client} =
      Sandbox.create_booking_link(Sandbox.fresh_state(), %{
        "client_name" => "Sally",
        "phone" => "8025551234",
        "job_type_label" => "sink repair",
        "duration_min_minutes" => 90,
        "duration_max_minutes" => 120
      })

    SchedulingAgentTest.save_session(user, business.id, state)

    assert {:ok, _} =
             SchedulingAgentTest.send_client(
               user,
               business.id,
               "STUB_CLARIFY {\"reply_sms\":\"Tuesday morning works for me.\"}"
             )

    state = SchedulingAgentTest.get_or_create_session(user, business.id)
    assert length(state["client_turns"]) == 2
    assert Enum.at(state["client_turns"], 1)["text"] == "Tuesday morning works for me."
  end

  test "reset clears sandbox state", %{user: user, business: business} do
    json =
      Jason.encode!(%{
        "assistant_sms" => "Lead saved.",
        "job_actions" => [
          %{
            "intent" => "create",
            "job" => %{
              "client_name" => "Test",
              "work_description" => "test",
              "status" => "lead",
              "priority" => "normal"
            }
          }
        ]
      })

    _ = SchedulingAgentTest.send_contractor(user, business.id, "STUB_JSON #{json}")
    _ = SchedulingAgentTest.reset_session(user, business.id)
    state = SchedulingAgentTest.get_or_create_session(user, business.id)
    assert length(state["jobs"]) == 0
    assert length(state["contractor_turns"]) == 1
  end
end
