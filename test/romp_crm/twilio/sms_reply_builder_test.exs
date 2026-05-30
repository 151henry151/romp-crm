defmodule RompCrm.Twilio.SmsReplyBuilderTest do
  use ExUnit.Case, async: true

  alias RompCrm.Jobs.Job
  alias RompCrm.Twilio.SmsReplyBuilder

  defp job!(name), do: %Job{id: 85, client_name: name, business_id: 6}

  describe "compose/2" do
    test "prefers photo save summary when assistant asks which job after photos were saved" do
      results = [{:photos_saved, job!("Dave Wohl"), 3, 3}]

      assistant =
        "Which job are these 3 photos for - Dave Wohl's estimate, or one of the other jobs?"

      assert SmsReplyBuilder.compose(assistant, results) ==
               "Got it—saved 3/3 photo(s) for Dave Wohl."
    end

    test "keeps non-clarifying assistant text when photos were saved" do
      results = [{:photos_saved, job!("Dave Wohl"), 3, 3}]

      assistant =
        "Attached photos to Dave Wohl's estimate job for shower pan, toilet, and kitchen sink work."

      assert SmsReplyBuilder.compose(assistant, results) == assistant
    end

    test "keeps clarifying assistant when no photos were saved" do
      results = []

      assistant = "Which job are these 3 photos for - Greg Gorman, Dave Wohl, or Mary Frank?"

      assert SmsReplyBuilder.compose(assistant, results) == assistant
    end

    test "appends skipped note when operations failed" do
      results = [{:error, :attach_photo_all_failed}]

      assert SmsReplyBuilder.compose("Ignored.", results) == "Ignored. (1 skipped.)"
    end

    test "replaces partial address assistant text with full saved service address" do
      job = %Job{
        id: 12,
        client_name: "Dave Miles",
        address_line1: "34 Exchange St",
        city: "Middlebury",
        state: "VT",
        postal_code: "05753"
      }

      results = [{:updated, job, ["address_line1", "city", "state", "postal_code"], []}]

      assistant = "Updated Dave Miles' address to 34 Exchange St"

      assert SmsReplyBuilder.compose(assistant, results) ==
               "Updated Dave Miles's address to 34 Exchange St, Middlebury, VT 05753."
    end

    test "replaces partial billing address assistant text with full saved billing address" do
      job = %Job{
        id: 12,
        client_name: "Dave Miles",
        billing_address_different: true,
        billing_address_line1: "45 Exchange St",
        billing_city: "Middlebury",
        billing_state: "VT",
        billing_postal_code: "05753"
      }

      results = [{:updated, job, ["billing_address_line1"], []}]

      assistant = "Updated Dave Miles' billing address to 45 Exchange St"

      assert SmsReplyBuilder.compose(assistant, results) ==
               "Updated Dave Miles's billing address to 45 Exchange St, Middlebury, VT 05753."
    end
  end
end
