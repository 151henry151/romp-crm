defmodule RompCrm.AgentChatTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.AgentChat
  alias RompCrm.ChatMedia
  alias RompCrm.Conversations
  alias RompCrm.JobUploads
  alias RompCrm.SmsConversations

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  setup do
    prev_dir = Application.get_env(:romp_crm, :job_photo_static_dir)

    dir = Path.join(System.tmp_dir!(), "romp-crm-agent-chat-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "uploads"))
    Application.put_env(:romp_crm, :job_photo_static_dir, dir)

    on_exit(fn ->
      if is_nil(prev_dir) do
        Application.delete_env(:romp_crm, :job_photo_static_dir)
      else
        Application.put_env(:romp_crm, :job_photo_static_dir, prev_dir)
      end

      File.rm_rf(dir)
    end)

    user = user_fixture()
    {:ok, user} = RompCrm.Accounts.update_user_profile(user, %{phone: "8025550100"})
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business, static_dir: dir}
  end

  test "send_message with media_urls stores photo URL on the inbound row", %{
    user: user,
    business: business
  } do
    jpeg = <<0xFF, 0xD8, 0xFF, 0xE0, "JFIF-agent-test">>
    assert {:ok, %{public_url: url, relative_path: rel}} = ChatMedia.store!(business.id, jpeg, "image/jpeg")
    assert File.regular?(JobUploads.absolute_path(rel))

    assert {:ok, _reply} =
             AgentChat.send_message(user, business.id, "what is in this photo?", media_urls: [url])

    msgs = SmsConversations.list_business_agent_messages(business.id)
    inbound = Enum.find(msgs, &(&1.direction == "inbound" and &1.channel == "in_app"))
    assert inbound
    assert inbound.body =~ url

    rows = Conversations.format_thread_rows(msgs, user, business.id)
    self_row = Enum.find(rows, &(&1.side == :right and url in (&1.photos || [])))
    assert self_row
  end

  test "send_message allows photo-only with empty caption", %{user: user, business: business} do
    jpeg = <<0xFF, 0xD8, 0xFF, 0xE0, "JFIF-only">>
    assert {:ok, %{public_url: url}} = ChatMedia.store!(business.id, jpeg, "image/jpeg")

    assert {:ok, _} = AgentChat.send_message(user, business.id, "", media_urls: [url])
  end
end
