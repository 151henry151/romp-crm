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
  end
end
