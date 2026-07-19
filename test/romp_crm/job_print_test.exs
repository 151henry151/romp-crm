defmodule RompCrm.JobPrintTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.Jobs
  alias RompCrm.JobPrint
  alias RompCrm.JobsFixtures
  alias RompCrm.TimeTrackingFixtures

  setup do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)
    dir = Path.join(System.tmp_dir!(), "romp-crm-job-print-test-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    Application.put_env(:romp_crm, :job_photo_static_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)

      if prev do
        Application.put_env(:romp_crm, :job_photo_static_dir, prev)
      else
        Application.delete_env(:romp_crm, :job_photo_static_dir)
      end
    end)

    business = JobsFixtures.business_fixture(%{name: "Print Job Co"})

    job =
      JobsFixtures.job_fixture(%{
        business_id: business.id,
        client_name: "Carolyn Brewer",
        phone: "+18023497583",
        address_line1: "10 Main St",
        city: "Middlebury",
        state: "VT",
        postal_code: "05753",
        work_description: "Remove cast iron drain pipes",
        status: :pending,
        priority: :high,
        notes: "Call before arrival",
        next_action: "Confirm materials",
        scheduled_on: ~D[2026-07-24]
      })

    %{business: business, job: job}
  end

  describe "build_job_report/2" do
    test "returns not_found for missing job", %{business: business} do
      assert {:error, :not_found} == JobPrint.build_job_report(999_999, business.id)
    end

    test "includes contact, schedule, work items, materials, hours, and photos", %{
      business: business,
      job: job
    } do
      assert {:ok, job} =
               Jobs.update_job(job, %{
                 "work_items" => [
                   %{"title" => "Cut pipes", "sort_order" => 0, "scheduled_on" => "2026-07-24"}
                 ],
                 "materials" => [
                   %{"description" => "PVC adapter", "quantity" => 2, "sort_order" => 0}
                 ]
               })

      TimeTrackingFixtures.time_entry_fixture(%{
        job_id: job.id,
        business_id: business.id,
        started_at: ~N[2026-07-18 09:00:00],
        ended_at: ~N[2026-07-18 11:30:00],
        notes: "Rough-in"
      })

      {:ok, _photo} =
        Jobs.add_job_photo(job, business.id, tiny_jpeg(), "image/jpeg", nil)

      assert {:ok, report} = JobPrint.build_job_report(job.id, business.id)

      assert report.job.client_name == "Carolyn Brewer"
      assert report.job.status == :pending
      assert report.job.priority == :high
      assert report.job.work_description =~ "cast iron"
      assert length(report.work_items) == 1
      assert hd(report.work_items).title == "Cut pipes"
      assert length(report.materials) == 1
      assert hd(report.materials).description == "PVC adapter"
      assert report.total_minutes == 150
      assert length(report.time_entries) == 1
      assert length(report.photos) == 1
      assert hd(report.photos).data_uri =~ "data:image/jpeg;base64,"
    end
  end

  describe "render_pdf/1" do
    test "returns PDF bytes and filename via stub adapter", %{business: business, job: job} do
      assert {:ok, report} = JobPrint.build_job_report(job.id, business.id)
      assert {:ok, pdf, filename} = JobPrint.render_pdf(report)

      assert is_binary(pdf)
      assert byte_size(pdf) > 0
      assert filename =~ "carolyn-brewer"
      assert String.ends_with?(filename, ".pdf")
    end
  end

  defp tiny_jpeg do
    # Minimal valid JPEG (1x1)
    Base.decode64!(
      "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEABj8Cf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAT8hf//Z"
    )
  end
end
