defmodule RompCrm.BusinessAuditLogs.DetailTest do
  use ExUnit.Case, async: true

  alias RompCrm.BusinessAuditLogs.Detail
  alias RompCrm.Jobs.Job
  describe "changes_from_job_patch/4" do
    test "materials in patch become material_added changes with quantity" do
      job = %Job{id: 12, client_name: "Celeste"}

      patch = %{
        "materials" => [%{"quantity" => 4, "description" => ~s(1/2" couplings)}]
      }

      changes = Detail.changes_from_job_patch(job, patch, nil, nil)

      assert [%{type: "material_added", quantity: 4.0, description: ~s(1/2" couplings)}] = changes
    end
  end

  describe "summary_from_changes/1" do
    test "formats material added for CSV summary" do
      summary =
        Detail.summary_from_changes([
          %{
            type: "material_added",
            job_id: 5,
            client_name: "Pat",
            quantity: 2.0,
            description: "wax seal"
          }
        ])

      assert summary =~ "Job #5 (Pat)"
      assert summary =~ "Added material"
      assert summary =~ "wax seal"
    end
  end

  describe "enrich/2" do
    test "adds summary and preserves sms bodies" do
      meta =
        Detail.enrich(%{client_name: "Pat"}, %{
          sms_inbound: "add 2 traps",
          sms_outbound: "Got it—updated Pat.",
          changes: [%{type: "material_added", description: "traps", quantity: 2.0}]
        })

      assert meta[:sms_inbound] == "add 2 traps"
      assert meta[:sms_outbound] == "Got it—updated Pat."
      assert meta[:summary] =~ "traps"
    end
  end

  describe "job_snapshot diff" do
    test "detects newly inserted material rows" do
      before = %{materials: [], work_items: [], scalars: %{}}

      after_snap = %{
        materials: [%{"id" => 99, "description" => "elbow", "quantity" => 3.0}],
        work_items: [],
        scalars: %{}
      }

      changes = Detail.changes_from_job_patch(%Job{id: 1}, %{}, before, after_snap)

      assert Enum.any?(changes, fn c ->
               (c[:type] || c["type"]) in ["material_added", :material_added]
             end)
    end
  end
end
