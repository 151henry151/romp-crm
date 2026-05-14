defmodule RompCrm.Jobs.MaterialSmsNormalizeTest do
  use ExUnit.Case, async: true

  alias RompCrm.Jobs.MaterialSmsNormalize

  describe "quantity_and_description/2" do
    test "leading integer ≥ 2 becomes quantity; remainder is description" do
      assert MaterialSmsNormalize.quantity_and_description(~s(2 1 1/4" p traps), 1) ==
               {2.0, ~s(1 1/4" p traps)}

      assert MaterialSmsNormalize.quantity_and_description(~s(2 1 1/4" p traps), nil) ==
               {2.0, ~s(1 1/4" p traps)}
    end

    test "spoken numbers become quantity" do
      assert MaterialSmsNormalize.quantity_and_description("one wax seal", 1) == {1.0, "wax seal"}
      assert MaterialSmsNormalize.quantity_and_description("ONE wax seal", 1) == {1.0, "wax seal"}

      assert MaterialSmsNormalize.quantity_and_description("two 1/2\" PRS 90s", 1) ==
               {2.0, ~s(1/2" PRS 90s)}
    end

    test "leading integer 1 is not peeled from description" do
      assert MaterialSmsNormalize.quantity_and_description(~s(1 1/4" elbow), 1) ==
               {1.0, ~s(1 1/4" elbow)}
    end

    test "explicit quantity > 1 is trusted; description unchanged" do
      assert MaterialSmsNormalize.quantity_and_description(~s(1 1/4" P traps), 2) ==
               {2.0, ~s(1 1/4" P traps)}
    end

    test "plain description without leading count" do
      assert MaterialSmsNormalize.quantity_and_description("wax seal", 1) == {1.0, "wax seal"}
    end
  end
end
