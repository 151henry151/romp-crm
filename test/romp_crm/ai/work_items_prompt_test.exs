defmodule RompCrm.Ai.WorkItemsPromptTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.WorkItemsPrompt

  test "guidance/0 documents create, add-on, and description-only rules" do
    text = WorkItemsPrompt.guidance()

    assert text =~ "Creates (new lead / new job)"
    assert text =~ "Fix toilet"
    assert text =~ "Replace bathtub"
    assert text =~ "description-only"
  end
end
