defmodule RompCrm.ChatMediaTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.ChatMedia
  alias RompCrm.JobUploads
  alias RompCrm.SmsMms

  import RompCrm.AccountsFixtures
  import RompCrm.JobsFixtures

  setup do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)
    dir = Path.join(System.tmp_dir!(), "romp-crm-chat-media-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "uploads"))
    Application.put_env(:romp_crm, :job_photo_static_dir, dir)

    on_exit(fn ->
      if is_nil(prev) do
        Application.delete_env(:romp_crm, :job_photo_static_dir)
      else
        Application.put_env(:romp_crm, :job_photo_static_dir, prev)
      end

      File.rm_rf(dir)
    end)

    user = user_fixture()
    business = business_fixture(%{owner_user: user})
    %{user: user, business: business, static_dir: dir}
  end

  test "store!/3 writes under uploads/chat-media and returns a public https URL", %{
    business: business
  } do
    jpeg = <<0xFF, 0xD8, 0xFF, 0xE0, "JFIF-test">>

    assert {:ok, %{relative_path: rel, public_url: url}} =
             ChatMedia.store!(business.id, jpeg, "image/jpeg")

    assert String.starts_with?(rel, "uploads/chat-media/#{business.id}/")
    assert String.ends_with?(rel, ".jpg")
    assert File.regular?(JobUploads.absolute_path(rel))
    assert String.contains?(url, "/uploads/chat-media/#{business.id}/")
    assert String.starts_with?(url, "http")
  end

  test "SmsMms.extract_media_urls/1 includes chat-media upload URLs" do
    body =
      "Hi\n\n[MMS attachments — 1 URL(s) stored for follow-up:]\n1. http://localhost:4000/romp-crm/uploads/chat-media/9/abc.jpg"

    assert SmsMms.extract_media_urls(body) == [
             "http://localhost:4000/romp-crm/uploads/chat-media/9/abc.jpg"
           ]
  end
end
