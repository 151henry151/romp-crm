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
end
