defmodule RompCrmWeb.JobsLivePhotoUploadTest do
  use RompCrmWeb.ConnCase

  import Phoenix.LiveViewTest
  import RompCrm.JobsFixtures

  alias RompCrm.Businesses
  alias RompCrm.JobUploads
  alias RompCrm.Jobs

  setup :register_and_log_in_user_with_business

  setup do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)
    dir = Path.join(System.tmp_dir!(), "romp-crm-photo-upload-test-#{System.unique_integer()}")
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

    :ok
  end

  test "Add photos modal includes fetch upload hook and url", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)

    job =
      job_fixture(%{
        business_id: business.id,
        client_name: "Photo Upload Client"
      })

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#job-row-#{job.id}")
    |> render_click()

    view
    |> element("#job-expand-md-#{job.id} button[phx-click=\"open_add_photos\"]")
    |> render_click()

    html = render(view)
    assert html =~ "job-photo-picker-#{job.id}"
    assert html =~ "JobPhotoUpload"
    assert html =~ "/jobs/#{job.id}/photos"
    assert html =~ "data-role=\"gallery-input\""
    assert html =~ "data-role=\"camera-input\""
  end

  test "job_photo_uploaded event refreshes job photos", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)
    job = job_fixture(%{business_id: business.id, client_name: "Refresh Client"})

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#job-row-#{job.id}")
    |> render_click()

    view
    |> element("#job-expand-md-#{job.id} button[phx-click=\"open_add_photos\"]")
    |> render_click()

    bytes = File.read!(fixture_jpeg_path())
    assert {:ok, _} = Jobs.add_job_photo(job, business.id, bytes, "image/jpeg")

    render_click(view, "job_photo_uploaded", %{"count" => "1"})

    assert render(view) =~ "1 photo saved on this job."
    job = Jobs.get_job!(job.id, business.id)
    assert length(job.photos) == 1
    assert File.exists?(JobUploads.absolute_path(hd(job.photos).relative_path))
  end

  defp fixture_jpeg_path do
    Path.expand("../../support/fixtures/test-photo.jpg", __DIR__)
  end
end
