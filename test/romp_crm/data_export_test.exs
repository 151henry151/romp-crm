defmodule RompCrm.DataExportTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.Accounts.User
  alias RompCrm.AccountsFixtures
  alias RompCrm.Businesses
  alias RompCrm.DataExport
  alias RompCrm.DataExportSchedule
  alias RompCrm.JobsFixtures

  describe "normalize_export_kinds/1" do
    test "returns error when nothing valid is selected" do
      assert {:error, :none_selected} == DataExport.normalize_export_kinds(%{})
      assert {:error, :none_selected} == DataExport.normalize_export_kinds(%{"export_kinds" => []})
      assert {:error, :none_selected} == DataExport.normalize_export_kinds(%{"export_kinds" => ["nope"]})
    end

    test "returns kinds in canonical order and dedupes" do
      params = %{
        "export_kinds" => ["audit_log", "jobs", "jobs", "employees"]
      }

      assert {:ok, [:jobs, :employees, :audit_log]} == DataExport.normalize_export_kinds(params)
    end

    test "accepts a single string export_kinds" do
      assert {:ok, [:time_log]} ==
               DataExport.normalize_export_kinds(%{"export_kinds" => "time_log"})
    end
  end

  describe "build_export_files/2" do
    test "returns only requested filenames in order" do
      assert [{"jobs.csv", _}, {"audit_log.csv", _}] =
               DataExport.build_export_files([1, 2], [:jobs, :audit_log])
    end
  end

  describe "build_download_payload/1" do
    test "returns one tuple for a single file" do
      body = "a,b\n1,2\n"
      assert {:ok, {:one, "jobs.csv", ^body}} =
               DataExport.build_download_payload([{"jobs.csv", body}])
    end

    test "returns error for empty list" do
      assert {:error, :empty} == DataExport.build_download_payload([])
    end

    test "returns zip bytes for multiple files" do
      files = [{"a.csv", "x\n"}, {"b.csv", "y\n"}]
      assert {:ok, {:zip, zip}} = DataExport.build_download_payload(files)
      assert is_binary(zip)
      assert binary_part(zip, 0, 2) == "PK"
    end
  end

  describe "normalize_export_business_ids/2" do
    test "returns error when user owns no businesses" do
      user = AccountsFixtures.user_fixture()
      assert {:error, :no_owned_businesses} == DataExport.normalize_export_business_ids(user, %{})
    end

    test "returns error when no workspace is selected" do
      owner = AccountsFixtures.user_fixture()
      {:ok, _} = Businesses.create_business(owner, %{name: "Co"})
      assert {:error, :no_business_selected} == DataExport.normalize_export_business_ids(owner, %{})
      assert {:error, :no_business_selected} ==
               DataExport.normalize_export_business_ids(owner, %{"export_business_ids" => []})
    end

    test "ignores ids that are not owned and returns sorted subset" do
      owner = AccountsFixtures.user_fixture()
      {:ok, b1} = Businesses.create_business(owner, %{name: "Zed"})
      {:ok, b2} = Businesses.create_business(owner, %{name: "Aye"})
      junk = 999_999_999

      params = %{
        "export_business_ids" => [to_string(b2.id), to_string(b1.id), to_string(junk)]
      }

      assert {:ok, ids} = DataExport.normalize_export_business_ids(owner, params)
      assert ids == Enum.sort([b1.id, b2.id])
    end

    test "accepts a single string export_business_ids" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "Solo"})
      assert {:ok, ids} = DataExport.normalize_export_business_ids(owner, %{"export_business_ids" => to_string(biz.id)})
      assert ids == [biz.id]
    end

    test "returns no_business_selected when only non-owned ids are given" do
      owner = AccountsFixtures.user_fixture()
      {:ok, _} = Businesses.create_business(owner, %{name: "Mine"})
      assert {:error, :no_business_selected} ==
               DataExport.normalize_export_business_ids(owner, %{
                 "export_business_ids" => ["999999999"]
               })
    end
  end

  describe "export_form_selected_kind_strings/1 and export_form_selected_business_ids/2" do
    test "defaults when json columns are nil" do
      user = %User{data_export_kinds_json: nil, data_export_business_ids_json: nil}
      owned = [%{id: 10}, %{id: 20}]

      assert DataExport.export_form_selected_kind_strings(user) == [
               "jobs",
               "employees",
               "time_log",
               "audit_log"
             ]

      assert DataExport.export_form_selected_business_ids(user, owned) == [10, 20]
    end

    test "reads saved json lists" do
      user = %User{
        data_export_kinds_json: ~s(["employees","jobs"]),
        data_export_business_ids_json: "[2,1]"
      }

      owned = [%{id: 1}, %{id: 2}, %{id: 3}]
      assert DataExport.export_form_selected_kind_strings(user) == ["jobs", "employees"]
      assert DataExport.export_form_selected_business_ids(user, owned) == [1, 2]
    end
  end

  describe "compute_next_run_at/2" do
    test "advances by one interval" do
      from = ~U[2026-05-10 12:00:00Z]
      assert ~U[2026-05-11 12:00:00Z] == DataExportSchedule.compute_next_run_at("daily", from)
      assert ~U[2026-05-17 12:00:00Z] == DataExportSchedule.compute_next_run_at("weekly", from)
      assert ~U[2026-06-09 12:00:00Z] == DataExportSchedule.compute_next_run_at("monthly", from)
    end
  end

  describe "build_jobs_csv/1" do
    test "includes only jobs for given business ids" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "Owned Co"})
      other = AccountsFixtures.user_fixture()
      {:ok, other_biz} = Businesses.create_business(other, %{name: "Other"})

      {:ok, j1} =
        RompCrm.Jobs.create_job(%{
          "business_id" => biz.id,
          "client_name" => "A",
          "priority" => "normal",
          "status" => "lead"
        })

      {:ok, _j2} =
        RompCrm.Jobs.create_job(%{
          "business_id" => other_biz.id,
          "client_name" => "Secret",
          "priority" => "normal",
          "status" => "lead"
        })

      csv = DataExport.build_jobs_csv([biz.id])
      assert csv =~ "A"
      refute csv =~ "Secret"
      assert csv =~ to_string(j1.id)
    end

    test "includes only jobs for the given business id subset" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz1} = Businesses.create_business(owner, %{name: "One"})
      {:ok, biz2} = Businesses.create_business(owner, %{name: "Two"})

      {:ok, j1} =
        RompCrm.Jobs.create_job(%{
          "business_id" => biz1.id,
          "client_name" => "OnlyOne",
          "priority" => "normal",
          "status" => "lead"
        })

      {:ok, _} =
        RompCrm.Jobs.create_job(%{
          "business_id" => biz2.id,
          "client_name" => "OnlyTwo",
          "priority" => "normal",
          "status" => "lead"
        })

      csv = DataExport.build_jobs_csv([biz1.id])
      assert csv =~ "OnlyOne"
      refute csv =~ "OnlyTwo"
      assert csv =~ to_string(j1.id)
    end
  end

  describe "build_audit_log_csv/1" do
    test "includes audit rows for owned business ids" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "Audit Co"})

      RompCrm.BusinessAuditLogs.record(%{
        business_id: biz.id,
        actor_user_id: owner.id,
        source: "web",
        action: "jobs.create",
        entity_type: "jobs",
        entity_id: 42,
        metadata: %{}
      })

      csv = DataExport.build_audit_log_csv([biz.id])
      assert csv =~ "jobs.create"
      assert csv =~ owner.email
      assert csv =~ "42"
      assert csv =~ "summary"
      assert csv =~ "sms_inbound"
      assert csv =~ "sms_outbound"
      assert csv =~ "changes"
    end
  end

  describe "build_time_log_csv/1" do
    test "includes job time rows for business" do
      owner = AccountsFixtures.user_fixture()
      {:ok, biz} = Businesses.create_business(owner, %{name: "T Co"})
      job = JobsFixtures.job_fixture(%{business_id: biz.id, client_name: "Client Z"})

      {:ok, _} =
        RompCrm.TimeTracking.create_time_entry(%{
          business_id: biz.id,
          job_id: job.id,
          started_at: ~N[2026-05-11 09:00:00],
          ended_at: ~N[2026-05-11 10:00:00]
        })

      csv = DataExport.build_time_log_csv([biz.id])
      assert csv =~ "job_time"
      assert csv =~ "Client Z"
    end
  end
end
