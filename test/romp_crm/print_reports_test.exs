defmodule RompCrm.PrintReportsTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.AccountsFixtures
  alias RompCrm.Businesses
  alias RompCrm.Clients
  alias RompCrm.EmployeesFixtures
  alias RompCrm.JobsFixtures
  alias RompCrm.PrintReports
  alias RompCrm.TimeTrackingFixtures

  describe "normalize_report_type/1" do
    test "accepts activity and customers" do
      assert {:ok, :activity} == PrintReports.normalize_report_type(%{"report_type" => "activity"})
      assert {:ok, :customers} == PrintReports.normalize_report_type(%{"report_type" => "customers"})
    end

    test "rejects missing or invalid type" do
      assert {:error, :invalid_report_type} == PrintReports.normalize_report_type(%{})
      assert {:error, :invalid_report_type} ==
               PrintReports.normalize_report_type(%{"report_type" => "nope"})
    end
  end

  describe "normalize_date_range/1" do
    test "parses inclusive from/to dates" do
      assert {:ok, ~D[2026-07-01], ~D[2026-07-15]} ==
               PrintReports.normalize_date_range(%{
                 "from_date" => "2026-07-01",
                 "to_date" => "2026-07-15"
               })
    end

    test "rejects inverted or missing dates" do
      assert {:error, :invalid_date_range} == PrintReports.normalize_date_range(%{})

      assert {:error, :invalid_date_range} ==
               PrintReports.normalize_date_range(%{
                 "from_date" => "2026-07-15",
                 "to_date" => "2026-07-01"
               })
    end
  end

  describe "build_activity_report/3" do
    setup do
      owner = AccountsFixtures.user_fixture()
      {:ok, business} = Businesses.create_business(owner, %{name: "Report Co"})
      %{business: business, owner: owner}
    end

    test "includes job hours in range", %{business: business} do
      job =
        JobsFixtures.job_fixture(%{
          business_id: business.id,
          client_name: "Acme",
          status: :in_progress
        })

      TimeTrackingFixtures.time_entry_fixture(%{
        job_id: job.id,
        business_id: business.id,
        started_at: ~N[2026-07-10 09:00:00],
        ended_at: ~N[2026-07-10 11:00:00]
      })

      # Outside range
      TimeTrackingFixtures.time_entry_fixture(%{
        job_id: job.id,
        business_id: business.id,
        started_at: ~N[2026-06-01 09:00:00],
        ended_at: ~N[2026-06-01 10:00:00]
      })

      report =
        PrintReports.build_activity_report([business.id], ~D[2026-07-01], ~D[2026-07-31])

      assert report.summary.job_minutes == 120
      assert length(report.job_hours) == 1
      assert hd(report.job_hours).client_name == "Acme"
      assert hd(report.job_hours).minutes == 120
    end

    test "includes clock punches overlapping the range", %{business: business} do
      emp = EmployeesFixtures.employee_fixture(%{business_id: business.id, name: "Pat"})

      EmployeesFixtures.employee_time_entry_fixture(%{
        employee_id: emp.id,
        business_id: business.id,
        clocked_in_at: ~N[2026-07-12 08:00:00],
        clocked_out_at: ~N[2026-07-12 16:00:00],
        lunch_start_at: ~N[2026-07-12 12:00:00],
        lunch_end_at: ~N[2026-07-12 12:30:00],
        clock_in_kind: :live_punch,
        clock_out_kind: :live_punch
      })

      report =
        PrintReports.build_activity_report([business.id], ~D[2026-07-01], ~D[2026-07-31])

      assert report.summary.employee_worked_minutes == 450
      assert length(report.clock_punches) == 1
      assert hd(report.clock_punches).employee_name == "Pat"
      assert hd(report.clock_punches).worked_minutes == 450
    end

    test "includes open jobs and done jobs updated in range", %{business: business} do
      lead =
        JobsFixtures.job_fixture(%{
          business_id: business.id,
          client_name: "New Lead",
          status: :lead
        })

      pending =
        JobsFixtures.job_fixture(%{
          business_id: business.id,
          client_name: "Pending Job",
          status: :pending,
          scheduled_on: ~D[2026-08-01]
        })

      done_in_range =
        JobsFixtures.job_fixture(%{
          business_id: business.id,
          client_name: "Done In Range",
          status: :done
        })

      done_outside =
        JobsFixtures.job_fixture(%{
          business_id: business.id,
          client_name: "Done Outside",
          status: :done
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      in_range = DateTime.new!(~D[2026-07-10], ~T[15:00:00], "Etc/UTC")
      outside = DateTime.new!(~D[2026-06-01], ~T[15:00:00], "Etc/UTC")

      RompCrm.Repo.update_all(
        from(j in RompCrm.Jobs.Job, where: j.id == ^done_in_range.id),
        set: [updated_at: in_range]
      )

      RompCrm.Repo.update_all(
        from(j in RompCrm.Jobs.Job, where: j.id == ^done_outside.id),
        set: [updated_at: outside, inserted_at: outside]
      )

      # Touch unrelated fields should not matter; keep lead current
      _ = now

      report =
        PrintReports.build_activity_report([business.id], ~D[2026-07-01], ~D[2026-07-31])

      job_ids = Enum.map(report.jobs, & &1.id)
      assert lead.id in job_ids
      assert pending.id in job_ids
      assert done_in_range.id in job_ids
      refute done_outside.id in job_ids
    end
  end

  describe "build_customer_list/1" do
    test "returns clients with job counts for selected businesses" do
      owner = AccountsFixtures.user_fixture()
      {:ok, business} = Businesses.create_business(owner, %{name: "Clients Co"})

      {:ok, client} =
        Clients.create_client(%{
          business_id: business.id,
          client_name: "Jordan Client",
          phone: "+18025550199",
          client_email: "jordan@example.com",
          address_line1: "1 Main St",
          city: "Montpelier",
          state: "VT",
          postal_code: "05602",
          notes: "VIP"
        })

      JobsFixtures.job_fixture(%{
        business_id: business.id,
        client_id: client.id,
        client_name: "Jordan Client"
      })

      list = PrintReports.build_customer_list([business.id])
      assert length(list.customers) == 1
      row = hd(list.customers)
      assert row.client_name == "Jordan Client"
      assert row.phone == "+18025550199"
      assert row.client_email == "jordan@example.com"
      assert row.job_count == 1
      assert row.notes == "VIP"
    end
  end

  describe "Html.activity_document/4" do
    test "uses date-range headline without brand, workspace, or generated line" do
      report = %{
        summary: %{
          job_minutes: 0,
          employee_worked_minutes: 0
        },
        job_hours: [],
        clock_punches: [],
        jobs: [],
        businesses: [%{id: 1, name: "Secret Workspace"}]
      }

      html =
        RompCrm.PrintReports.Html.activity_document(
          report,
          ~D[2026-07-01],
          ~D[2026-07-16],
          ~U[2026-07-16 02:09:00Z]
        )

      assert html =~ "Report for Jul 01, 2026 – Jul 16, 2026"
      assert html =~ ">Jobs<"
      refute html =~ "Romp CRM"
      refute html =~ "ROMP"
      refute html =~ "Secret Workspace"
      refute html =~ "Generated"
      refute html =~ "Activity report"
      refute html =~ "New leads"
      refute html =~ "Jobs worked on"
      refute html =~ "Open leads and jobs"
    end
  end

  describe "Html.customers_document/2" do
    test "omits brand, workspace name, and generated line" do
      report = %{
        customers: [
          %{
            client_name: "Pat",
            business_name: "Hidden Co",
            phone: nil,
            client_email: nil,
            address: nil,
            billing_address: "Same as service",
            notes: nil,
            job_count: 0
          }
        ],
        businesses: [%{id: 1, name: "Hidden Co"}]
      }

      html =
        RompCrm.PrintReports.Html.customers_document(report, ~U[2026-07-16 02:09:00Z])

      assert html =~ "Customer list"
      refute html =~ "Romp CRM"
      refute html =~ "Hidden Co"
      refute html =~ "Workspace"
      refute html =~ "Generated"
    end
  end

  describe "render_pdf/2" do
    test "renders activity pdf bytes via stub adapter" do
      report = %{
        summary: %{
          job_minutes: 0,
          employee_worked_minutes: 0
        },
        job_hours: [],
        clock_punches: [],
        jobs: [],
        businesses: [%{id: 1, name: "Demo"}]
      }

      assert {:ok, pdf, filename} =
               PrintReports.render_pdf(:activity, report,
                 from_date: ~D[2026-07-01],
                 to_date: ~D[2026-07-15],
                 generated_at: ~U[2026-07-15 12:00:00Z]
               )

      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
      assert filename =~ "activity"
      assert filename =~ ".pdf"
    end

    test "renders customers pdf bytes via stub adapter" do
      report = %{customers: [], businesses: [%{id: 1, name: "Demo"}]}

      assert {:ok, pdf, filename} =
               PrintReports.render_pdf(:customers, report, generated_at: ~U[2026-07-15 12:00:00Z])

      assert String.starts_with?(pdf, "%PDF")
      assert filename =~ "customers"
    end
  end
end
