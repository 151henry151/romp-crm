defmodule RompCrm.ClientChatsTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.ClientChats
  alias RompCrm.SmsConversations

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  setup do
    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business, phone: "18025551234"}
  end

  test "take_over records intro SMS and sets takeover row", %{user: user, business: business, phone: phone} do
    assert :ok = ClientChats.take_over!(user, business.id, phone)
    assert ClientChats.taken_over?(business.id, phone)

    msgs = SmsConversations.list_client_thread_messages(business.id, phone)
    assert Enum.any?(msgs, &(&1.channel == "sms_human" and &1.direction == "outbound"))
  end

  test "hand_off clears takeover and records notice SMS", %{user: user, business: business, phone: phone} do
    :ok = ClientChats.take_over!(user, business.id, phone)
    assert :ok = ClientChats.hand_off!(user, business.id, phone)
    refute ClientChats.taken_over?(business.id, phone)
  end

  test "send_human_message requires takeover", %{user: user, business: business, phone: phone} do
    assert {:error, :not_taken_over} =
             ClientChats.send_human_message!(user, business.id, phone, "Hello")
  end

  test "send_human_message after takeover records outbound sms_human", %{
    user: user,
    business: business,
    phone: phone
  } do
    :ok = ClientChats.take_over!(user, business.id, phone)
    assert {:ok, "Hi there"} = ClientChats.send_human_message!(user, business.id, phone, "Hi there")

    msgs = SmsConversations.list_client_thread_messages(business.id, phone)
    assert Enum.count(msgs, &(&1.channel == "sms_human" and &1.body == "Hi there")) == 1
  end
end
