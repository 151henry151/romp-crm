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

  test "client scope question escalates to contractor pane", %{user: user, business: business} do
    {:ok, state, _link, _client} =
      Sandbox.create_booking_link(Sandbox.fresh_state(), %{
        "client_name" => "Peter",
        "phone" => "18025551234",
        "job_type_label" => "toilet flange replacement",
        "duration_min_minutes" => 90,
        "duration_max_minutes" => 120
      })

    SchedulingAgentTest.save_session(user, business.id, state)

    json =
      Jason.encode!(%{
        "reply_sms" =>
          "To add a kitchen sink faucet swap, let me check with our team to make sure we can take care of that for you. I'll get right back to you.",
        "action" => %{
          "type" => "escalate_question",
          "question_text" => "Can you also swap my kitchen sink faucet while you're there?"
        }
      })

    assert {:ok, _} =
             SchedulingAgentTest.send_client(user, business.id, "STUB_CLARIFY #{json}")

    state = SchedulingAgentTest.get_or_create_session(user, business.id)

    assert Enum.any?(state["contractor_turns"], fn turn ->
             turn["role"] == "assistant" and
               String.contains?(turn["text"], "kitchen sink faucet")
           end)
  end

  test "contractor escalation reply does not crash and prompts memory offer", %{
    user: user,
    business: business
  } do
    {:ok, state, _link, _client} =
      Sandbox.create_booking_link(Sandbox.fresh_state(), %{
        "client_name" => "Sally",
        "phone" => "18025551234",
        "job_type_label" => "sink repair",
        "duration_min_minutes" => 90,
        "duration_max_minutes" => 120
      })

    SchedulingAgentTest.save_session(user, business.id, state)

    json =
      Jason.encode!(%{
        "reply_sms" => "Let me check with our team.",
        "action" => %{
          "type" => "escalate_question",
          "question_text" => "How many people will be coming for the sink repair?"
        }
      })

    assert {:ok, _} =
             SchedulingAgentTest.send_client(user, business.id, "STUB_CLARIFY #{json}")

    escalation_json =
      Jason.encode!(%{
        "reply_sms" => "Ok — I'll let Sally know.",
        "resolved_escalation_id" => 1,
        "intent" => "provide_answer",
        "contractor_answer" => "Two people will be coming for the sink repair."
      })

    assert {:ok, _meta} =
             SchedulingAgentTest.send_contractor(
               user,
               business.id,
               "STUB_ESCALATION #{escalation_json}"
             )

    state = SchedulingAgentTest.get_or_create_session(user, business.id)

    [escalation] = state["pending_escalations"]

    assert escalation["status"] == "pending_memory_confirm"
    assert escalation["contractor_answer"] == "Two people will be coming for the sink repair."

    assert Enum.any?(state["contractor_turns"], fn turn ->
             turn["role"] == "assistant" and String.contains?(turn["text"], "Sally")
           end)
  end

  test "confirmed booking notifies contractor pane", %{user: user, business: business} do
    {:ok, state, link, _client} =
      Sandbox.create_booking_link(Sandbox.fresh_state(), %{
        "client_name" => "Peter",
        "phone" => "18025551234",
        "job_type_label" => "toilet flange replacement",
        "duration_min_minutes" => 90,
        "duration_max_minutes" => 120,
        "job_id" => nil
      })

    {:ok, state, job} =
      Sandbox.create_job(state, %{
        "client_name" => "Peter",
        "work_description" => "toilet flange replacement",
        "status" => "lead"
      })

    link = Map.put(link, "job_id", job["id"])

    links =
      Enum.map(state["booking_links"], fn l ->
        if l["id"] == link["id"], do: link, else: l
      end)

    state = state |> Map.put("booking_links", links)
    SchedulingAgentTest.save_session(user, business.id, state)

    starts =
      DateTime.utc_now()
      |> DateTime.add(5, :day)
      |> DateTime.truncate(:second)

    ends = DateTime.add(starts, 90, :minute)

    json =
      Jason.encode!(%{
        "reply_sms" => "You're all set!",
        "action" => %{
          "type" => "hard_booking",
          "starts_at" => DateTime.to_iso8601(starts),
          "ends_at" => DateTime.to_iso8601(ends)
        }
      })

    assert {:ok, _} = SchedulingAgentTest.send_client(user, business.id, "STUB_BOOK #{json}")

    state = SchedulingAgentTest.get_or_create_session(user, business.id)

    assert Enum.any?(state["contractor_turns"], fn turn ->
             turn["role"] == "assistant" and String.contains?(turn["text"], "we've scheduled")
           end)
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
