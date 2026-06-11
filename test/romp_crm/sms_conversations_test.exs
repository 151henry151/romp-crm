defmodule RompCrm.SmsConversationsTest do
  use RompCrm.DataCase

  alias RompCrm.SmsConversations

  setup do
    user = RompCrm.AccountsFixtures.user_fixture()
    {:ok, biz} = RompCrm.Businesses.create_business(user, %{name: "SMS Thread Co"})
    {:ok, user: user, business: biz}
  end

  test "record_exchange and list_prior_turns_for_ai return chronology for prompts", %{
    user: user,
    business: biz
  } do
    phone = "18025550199"

    assert {:ok, _} =
             SmsConversations.record_exchange(
               biz.id,
               user.id,
               phone,
               "clock in at Kevin's",
               "Clocked in."
             )

    assert {:ok, _} =
             SmsConversations.record_exchange(
               biz.id,
               user.id,
               phone,
               "That was Bob",
               "Got it — attributed to Bob."
             )

    turns = SmsConversations.list_prior_turns_for_ai(biz.id, phone)

    assert [
             {:contractor, "clock in at Kevin's"},
             {:assistant, "Clocked in."},
             {:contractor, "That was Bob"},
             {:assistant, "Got it — attributed to Bob."}
           ] == turns
  end

  test "trim_thread drops oldest turns when formatted thread exceeds max_chars", %{
    user: user,
    business: biz
  } do
    phone = "18025550200"

    long = String.duplicate("x", 5000)

    assert {:ok, _} =
             SmsConversations.record_exchange(biz.id, user.id, phone, "first", "reply a")

    assert {:ok, _} =
             SmsConversations.record_exchange(biz.id, user.id, phone, long, "reply b")

    turns = SmsConversations.list_prior_turns_for_ai(biz.id, phone, max_chars: 100)

    refute Enum.any?(turns, fn {_, t} -> t == "first" end)

    formatted =
      Enum.map(turns, fn {role, text} ->
        lab = if role == :assistant, do: "Assistant", else: "Contractor"
        "#{lab}: #{text}"
      end)
      |> Enum.join("\n")

    assert String.length(formatted) <= 100
    assert List.last(turns) == {:assistant, "reply b"}
  end

  describe "client threads (booking conversations)" do
    test "record_client_message and list_client_turns_for_ai keep a separate thread", %{
      user: user,
      business: biz
    } do
      phone = "18025550300"

      assert {:ok, _} =
               SmsConversations.record_client_message(
                 biz.id,
                 user.id,
                 phone,
                 "outbound",
                 "Hi Bob, this is Test Co about your flange replacement..."
               )

      assert {:ok, _} =
               SmsConversations.record_client_message(
                 biz.id,
                 user.id,
                 phone,
                 "inbound",
                 "Tuesday at 2pm works"
               )

      turns = SmsConversations.list_client_turns_for_ai(biz.id, phone)

      assert [
               {:assistant, "Hi Bob, this is Test Co about your flange replacement..."},
               {:client, "Tuesday at 2pm works"}
             ] == turns
    end

    test "contractor thread queries exclude client-thread rows for the same phone", %{
      user: user,
      business: biz
    } do
      phone = "18025550301"

      assert {:ok, _} =
               SmsConversations.record_exchange(biz.id, user.id, phone, "contractor msg", "ok")

      assert {:ok, _} =
               SmsConversations.record_client_message(biz.id, user.id, phone, "inbound", "client msg")

      contractor_turns = SmsConversations.list_prior_turns_for_ai(biz.id, phone)
      refute Enum.any?(contractor_turns, fn {_, t} -> t == "client msg" end)

      client_turns = SmsConversations.list_client_turns_for_ai(biz.id, phone)
      refute Enum.any?(client_turns, fn {_, t} -> t == "contractor msg" end)

      agent_msgs = SmsConversations.list_business_agent_messages(biz.id)
      refute Enum.any?(agent_msgs, &(&1.body == "client msg"))
    end
  end
end
