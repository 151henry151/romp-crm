defmodule RompCrm.ConversationsTest do
  use RompCrm.DataCase

  alias RompCrm.Conversations
  alias RompCrm.SmsConversations

  setup do
    user = RompCrm.AccountsFixtures.user_fixture()
    {:ok, biz} = RompCrm.Businesses.create_business(user, %{name: "Chat Co"})
    {:ok, user: user, business: biz}
  end

  test "format_thread_rows labels agent, self, and teammate", %{user: user, business: biz} do
    other = RompCrm.AccountsFixtures.user_fixture()

    assert {:ok, _} =
             SmsConversations.record_exchange(
               biz.id,
               user.id,
               "18025550111",
               "My note",
               "Agent reply to me"
             )

    assert {:ok, _} =
             SmsConversations.record_exchange(
               biz.id,
               other.id,
               "18025550222",
               "Teammate note",
               "Agent reply to teammate"
             )

    rows =
      :agent
      |> Conversations.list_thread_messages(biz.id)
      |> Conversations.format_thread_rows(user, biz.id)

    assert length(rows) == 4

    [mine_in, mine_out, theirs_in, _their_out] = rows

    assert mine_in.label == "You (sms)"
    assert mine_in.side == :right
    assert mine_in.role == :self
    assert mine_in.text == "My note"

    assert mine_out.label == "RompCRM agent"
    assert mine_out.side == :left
    assert mine_out.role == :agent

    assert theirs_in.label == "Team member"
    assert theirs_in.side == :right
    assert theirs_in.role == :employee
  end

  test "format_thread_rows shows You for in-app and You (sms) for sms", %{user: user, business: biz} do
    assert {:ok, _} =
             SmsConversations.record_exchange(
               biz.id,
               user.id,
               "18025550111",
               "From chat",
               "Reply",
               channel: "in_app"
             )

    assert {:ok, _} =
             SmsConversations.record_exchange(
               biz.id,
               user.id,
               "18025550111",
               "From phone",
               "Reply 2"
             )

    rows =
      :agent
      |> Conversations.list_thread_messages(biz.id)
      |> Conversations.format_thread_rows(user, biz.id)
      |> Enum.filter(&(&1.role == :self))

    assert Enum.at(rows, 0).label == "You"
    assert Enum.at(rows, 1).label == "You (sms)"
  end
end
