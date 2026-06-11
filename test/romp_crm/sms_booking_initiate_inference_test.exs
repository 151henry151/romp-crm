defmodule RompCrm.SmsBookingInitiateInferenceTest do
  use ExUnit.Case, async: true

  alias RompCrm.SmsBookingInitiateInference

  test "infers initiate when create has phone and work" do
    job_ops = [
      {:create,
       %{
         client_name: "Jasmine Blair",
         phone: "8027349389",
         work_description: "fix camping sink"
       }}
    ]

    assert [{:booking_initiate, attrs}] =
             SmsBookingInitiateInference.supplement([], job_ops, "Jasmine wants her sink fixed")

    assert attrs.client_name == "Jasmine Blair"
    assert attrs.phone == "8027349389"
    assert attrs.job_type_label == "fix camping sink"
  end

  test "does not infer when booking ops already present" do
    existing = [{:booking_initiate, %{phone: "8027349389"}}]
    job_ops = [{:create, %{phone: "8027349389", work_description: "sink"}}]

    assert SmsBookingInitiateInference.supplement(existing, job_ops, "schedule with her") == []
  end

  test "does not infer for lead-only intent" do
    job_ops = [{:create, %{phone: "8027349389", work_description: "sink"}}]

    assert SmsBookingInitiateInference.supplement([], job_ops, "just add a lead, don't text them") ==
             []
  end
end
