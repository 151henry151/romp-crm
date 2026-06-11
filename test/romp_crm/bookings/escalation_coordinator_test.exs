defmodule RompCrm.Bookings.EscalationCoordinatorTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  alias RompCrm.Bookings
  alias RompCrm.Bookings.{EscalationCoordinator, Escalations}
  alias RompCrm.SmsConversations

  @client_phone "18025300293"

  defp setup_booking(_ctx) do
    user = user_fixture(%{phone: "+18025550199"})
    business = business_fixture(%{owner_user: user, name: "Green Mountain Plumbing"})

    {:ok, client} =
      RompCrm.Clients.create_client(%{
        business_id: business.id,
        client_name: "Sally Adams",
        phone: "+" <> @client_phone
      })

    {:ok, link} =
      Bookings.create_booking_link(%{
        business_id: business.id,
        technician_user_id: user.id,
        client_id: client.id,
        job_type_label: "washing machine replacement",
        client_phone_normalized: @client_phone
      })

    %{user: user, business: business, client: client, link: link}
  end

  setup :setup_booking

  describe "escalate_from_client/2" do
    test "creates an open escalation and notifies the contractor", %{link: link, business: business} do
      assert {:ok, escalation, reply} =
               EscalationCoordinator.escalate_from_client(link, %{
                 question_text: "Do you charge extra to dispose of my old washing machine?"
               })

      assert escalation.status == "pending_contractor"
      assert escalation.question_text =~ "washing machine"
      assert reply =~ "don't have the answer"

      assert [open] = Escalations.list_open_for_business(business.id)
      assert open.id == escalation.id
    end
  end

  describe "handle_contractor_message/3" do
    setup %{link: link} do
      {:ok, escalation, _} =
        EscalationCoordinator.escalate_from_client(link, %{
          question_text: "Do you charge extra to dispose of my old washing machine?"
        })

      %{escalation: escalation}
    end

    test "contractor can say they will reach out directly", %{user: user, business: business, escalation: escalation} do
      body =
        "STUB_ESCALATION " <>
          Jason.encode!(%{
            "reply_sms" => "Got it — I'll let Sally know you're calling her.",
            "resolved_escalation_id" => escalation.id,
            "intent" => "contractor_handling"
          })

      assert {:handled, reply} =
               EscalationCoordinator.handle_contractor_message(user, business.id, body)

      assert reply =~ "Sally"
      assert Escalations.get_escalation!(escalation.id).status == "contractor_handling"
      assert Escalations.list_open_for_business(business.id) == []
    end

    test "contractor answer prompts a memory offer before relaying", %{
      user: user,
      business: business,
      escalation: escalation
    } do
      body =
        "STUB_ESCALATION " <>
          Jason.encode!(%{
            "reply_sms" =>
              "Ok — I'll let Sally know. Should I remember that washing machine disposal is $35 for future questions like this?",
            "resolved_escalation_id" => escalation.id,
            "intent" => "provide_answer",
            "contractor_answer" => "We always charge $35 for disposing of old washing machines."
          })

      assert {:handled, reply} = EscalationCoordinator.handle_contractor_message(user, business.id, body)
      assert reply =~ "remember"

      updated = Escalations.get_escalation!(escalation.id)
      assert updated.status == "pending_memory_confirm"
      assert updated.contractor_answer =~ "$35"
      assert is_nil(updated.client_relayed_at)
    end

    test "memory confirmation relays to the client and stores a business memory", %{
      user: user,
      business: business,
      escalation: escalation,
      link: link
    } do
      {:ok, escalation} =
        Escalations.update_escalation(escalation, %{
          status: "pending_memory_confirm",
          contractor_answer: "We always charge $35 for disposing of old washing machines.",
          memory_candidate: "Washing machine disposal costs $35."
        })

      body =
        "STUB_ESCALATION " <>
          Jason.encode!(%{
            "reply_sms" => "Saved — I'll tell Sally.",
            "resolved_escalation_id" => escalation.id,
            "intent" => "memory_decision",
            "save_memory" => true
          })

      assert {:handled, _reply} = EscalationCoordinator.handle_contractor_message(user, business.id, body)

      assert Escalations.get_escalation!(escalation.id).status == "resolved"
      assert [memory] = Escalations.list_memories_for_business(business.id)
      assert memory.answer_text =~ "$35"

      turns = SmsConversations.list_client_turns_for_ai(business.id, @client_phone)
      assert Enum.any?(turns, fn {role, text} -> role == :assistant and text =~ "$35" end)

      assert link.id
    end

    test "returns :continue when the message is unrelated to an open escalation", %{
      user: user,
      business: business
    } do
      body =
        "STUB_ESCALATION " <>
          Jason.encode!(%{
            "reply_sms" => "",
            "resolved_escalation_id" => nil,
            "intent" => "not_escalation"
          })

      assert :continue = EscalationCoordinator.handle_contractor_message(user, business.id, body)
    end
  end
end
