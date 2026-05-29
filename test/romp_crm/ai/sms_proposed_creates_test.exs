defmodule RompCrm.Ai.SmsProposedCreatesTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsProposedCreates

  test "parse_list normalizes proposed job entries" do
    [one] =
      SmsProposedCreates.parse_list([
        %{
          "job" => %{
            "client_name" => "Jimmy Wang",
            "address" => "123 Bonehead Drive",
            "work_description" => "Leaking faucet"
          },
          "attach_media_urls" => ["https://api.twilio.com/Media/ME1"]
        }
      ])

    assert one.job_attrs[:client_name] == "Jimmy Wang"
    assert one.attach_media_urls == ["https://api.twilio.com/Media/ME1"]
  end
end
