defmodule RompCrmWeb.EndpointInvitationUrlTest do
  use ExUnit.Case, async: true

  describe "documented URL construction for mailed invitation links" do
    test "invitation suffix uses Endpoint.path/1 since url/0 omits mount path" do
      token = "raw-token-sample"
      suffix = RompCrmWeb.Endpoint.path("/invitations/#{token}")

      assert suffix =~ "/invitations/#{token}"
      refute suffix =~ "//invitations"
    end

    test "joining trimmed url() with invitation path avoids double slashes before invitations" do
      token = "abc"

      joined =
        RompCrmWeb.Endpoint.url()
        |> String.trim_trailing("/")
        |> Kernel.<>(RompCrmWeb.Endpoint.path("/invitations/#{token}"))

      assert joined =~ "/invitations/abc"
      refute Regex.match?(~r{://[^/?#]+//invitations}, joined)
    end
  end
end
