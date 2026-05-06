defmodule JgsCrm.Ai.SmsJobExtractorTest do
  use ExUnit.Case, async: true

  alias JgsCrm.Ai.SmsJobExtractor

  describe "extract/2" do
    test "returns update_by_id when JSON includes job_id" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "intent" => "update",
            "job_id" => 44,
            "updates" => %{"address" => "99 Oak"}
          })

      assert {:ok, [{:update_by_id, 44, %{address: "99 Oak"}}]} = SmsJobExtractor.extract(raw, [])
    end

    test "returns legacy update tuple when job_id absent and match present" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "intent" => "update",
            "match" => %{"client_name" => "Pat"},
            "updates" => %{"phone" => "802"}
          })

      assert {:ok, [{:update, match, %{phone: "802"}}]} = SmsJobExtractor.extract(raw, [])
      assert match == %{"client_name" => "Pat"}
    end

    test "invalid job_id string returns error" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{"intent" => "update", "job_id" => "xyz", "updates" => %{"address" => "z"}})

      assert {:error, :invalid_job_id} = SmsJobExtractor.extract(raw, [])
    end

    test "returns multiple operations from actions array" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "create",
                "job" => %{"client_name" => "Mark Sino", "work_description" => "Replace refrigerator"}
              },
              %{
                "intent" => "create",
                "job" => %{"client_name" => "Dave Woll", "work_description" => "Clogged drain"}
              },
              %{
                "intent" => "update",
                "job_id" => 7,
                "updates" => %{"phone" => "8029897658"}
              }
            ]
          })

      assert {:ok,
              [
                {:create, %{client_name: "Mark Sino", work_description: "Replace refrigerator"}},
                {:create, %{client_name: "Dave Woll", work_description: "Clogged drain"}},
                {:update_by_id, 7, %{phone: "8029897658"}}
              ]} = SmsJobExtractor.extract(raw, [])
    end
  end
end
