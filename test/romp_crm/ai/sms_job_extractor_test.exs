defmodule RompCrm.Ai.SmsJobExtractorTest do
  use ExUnit.Case, async: true

  alias RompCrm.Ai.SmsJobExtractor

  describe "normalize_update_patch/1" do
    test "preserves material quantity from AI JSON for update patches" do
      patch =
        SmsJobExtractor.normalize_update_patch(%{
          "materials" => [
            %{"quantity" => 5, "description" => ~s(1/2" couplings)}
          ]
        })

      assert [%{"description" => ~s(1/2" couplings), "quantity" => 5, "sort_order" => 0}] ==
               patch.materials
    end

    test "includes client_email in update patch" do
      patch =
        SmsJobExtractor.normalize_update_patch(%{
          "client_email" => "pat@example.com"
        })

      assert patch.client_email == "pat@example.com"
    end

    test "preserves string material quantity" do
      patch =
        SmsJobExtractor.normalize_update_patch(%{
          "materials" => [%{"quantity" => "3", "description" => "PVC tees"}]
        })

      assert [%{"description" => "PVC tees", "quantity" => "3", "sort_order" => 0}] ==
               patch.materials
    end
  end

  describe "extract/2" do
    test "returns update_by_id when JSON includes job_id" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "intent" => "update",
            "job_id" => 44,
            "updates" => %{"address" => "99 Oak"}
          })

      assert {:ok,
              %{
                assistant_sms: "Stub: applied.",
                operations: [{:update_by_id, 44, %{address: "99 Oak"}}]
              }} =
               SmsJobExtractor.extract(raw, [])
    end

    test "returns legacy update tuple when job_id absent and match present" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "intent" => "update",
            "match" => %{"client_name" => "Pat"},
            "updates" => %{"phone" => "802"}
          })

      assert {:ok,
              %{assistant_sms: "Stub: applied.", operations: [{:update, match, %{phone: "802"}}]}} =
               SmsJobExtractor.extract(raw, [])

      assert match == %{"client_name" => "Pat"}
    end

    test "invalid job_id string returns error" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "intent" => "update",
            "job_id" => "xyz",
            "updates" => %{"address" => "z"}
          })

      assert {:error, :invalid_job_id} = SmsJobExtractor.extract(raw, [])
    end

    test "returns multiple operations from actions array" do
      raw =
        "STUB_JSON " <>
          Jason.encode!(%{
            "actions" => [
              %{
                "intent" => "create",
                "job" => %{
                  "client_name" => "Mark Sino",
                  "work_description" => "Replace refrigerator"
                }
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
              %{
                assistant_sms: "Stub: applied.",
                operations: [
                  {:create,
                   %{client_name: "Mark Sino", work_description: "Replace refrigerator"}},
                  {:create, %{client_name: "Dave Woll", work_description: "Clogged drain"}},
                  {:update_by_id, 7, %{phone: "8029897658"}}
                ]
              }} = SmsJobExtractor.extract(raw, [])
    end
  end
end
