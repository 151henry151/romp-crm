defmodule RompCrm.SmsPendingBookingProposalsTest do
  use RompCrm.DataCase

  alias RompCrm.SmsPendingBookingProposals

  describe "confirmation_message?/1" do
    test "matches short booking affirmatives" do
      assert SmsPendingBookingProposals.confirmation_message?("yes")
      assert SmsPendingBookingProposals.confirmation_message?("YES")
      assert SmsPendingBookingProposals.confirmation_message?("ok")
      assert SmsPendingBookingProposals.confirmation_message?("go ahead")
      assert SmsPendingBookingProposals.confirmation_message?("do it")
      assert SmsPendingBookingProposals.confirmation_message?("yes text them")
      assert SmsPendingBookingProposals.confirmation_message?("text her")
      assert SmsPendingBookingProposals.confirmation_message?("send the scheduling")
    end

    test "rejects longer messages that merely contain affirmation words" do
      refute SmsPendingBookingProposals.confirmation_message?(
               "That job for Christine, we're going to do it tomorrow"
             )

      refute SmsPendingBookingProposals.confirmation_message?(
               "Ok don't text the client, just mark the job as scheduled for tomorrow"
             )

      refute SmsPendingBookingProposals.confirmation_message?("Do that yes")

      refute SmsPendingBookingProposals.confirmation_message?(
               "Okay, now I am going to upload a photo, create a new lead from the information in the photo."
             )
    end
  end
end
