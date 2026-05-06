defmodule JgsCrm.Jobs.SmsMatchTest do
  use ExUnit.Case, async: true

  alias JgsCrm.Jobs.Job
  alias JgsCrm.Jobs.SmsMatch

  defp job(attrs) do
    struct!(
      Job,
      Enum.into(attrs, %{
        id: 1,
        client_name: nil,
        address: nil,
        phone: nil,
        work_description: nil,
        notes: nil,
        priority: :normal,
        status: :lead,
        referred_by: nil,
        next_action: nil
      })
    )
  end

  test "score/2 awards full points for exact client name" do
    j = job(%{client_name: "Angela Brande"})
    assert SmsMatch.score(j, %{"client_name" => "Angela Brande"}) == 120
  end

  test "score/2 matches client name substring" do
    j = job(%{client_name: "Angela Brande"})
    assert SmsMatch.score(j, %{"client_name" => "Angela"}) == 78
  end

  test "score/2 adds address_snippet when job address contains needle" do
    j = job(%{address: "32 Seminary Lane, Castleton VT"})
    assert SmsMatch.score(j, %{"address_snippet" => "32 Seminary"}) >= 38
  end

  test "score/2 adds work_description_snippet" do
    j = job(%{work_description: "Full bathroom remodel, second floor"})
    sc = SmsMatch.score(j, %{"work_description_snippet" => "bathroom remodel"})
    assert sc >= 48
  end

  test "score/2 matches work_description when model uses shut off vs CRM shutoff" do
    j = job(%{work_description: "Water shutoff"})
    sc = SmsMatch.score(j, %{"work_description_snippet" => "water shut off"})
    assert sc >= 48
  end

  test "score/2 matches work_description hyphen shut-off variant" do
    j = job(%{work_description: "Water shutoff"})
    sc = SmsMatch.score(j, %{"work_description_snippet" => "water shut-off"})
    assert sc >= 48
  end

  test "score/2 adds phone_fragment when digits match" do
    j = job(%{phone: "(802) 555-0199"})
    assert SmsMatch.score(j, %{"phone_fragment" => "0199"}) == 45
  end

  test "score/2 combines multiple hints" do
    j =
      job(%{
        client_name: "Bob Sinclair",
        address: "10 Oak Street",
        work_description: "Sump pump install basement"
      })

    multi =
      SmsMatch.score(j, %{
        "client_name" => "Bob",
        "address_snippet" => "Oak",
        "work_description_snippet" => "sump pump"
      })

    base = SmsMatch.score(j, %{"client_name" => "Bob"})
    assert multi > base
    assert multi >= 52 + 24 + 48
  end
end
