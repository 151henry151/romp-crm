defmodule RompCrmWeb.JobPhotoControllerTest do
  use RompCrmWeb.ConnCase

  import RompCrm.JobsFixtures

  alias RompCrm.Businesses
  alias RompCrm.JobUploads
  alias RompCrm.Jobs

  setup :register_and_log_in_user_with_business

  setup do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)
    dir = Path.join(System.tmp_dir!(), "romp-crm-photo-controller-test-#{System.unique_integer()}")
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

  test "creates a job photo and returns json", %{conn: conn, user: user} do
    [business] = Businesses.list_businesses_for_user(user)
    job = job_fixture(%{business_id: business.id})

    upload = %Plug.Upload{
      path: fixture_jpeg_path(),
      filename: "site.jpg",
      content_type: "image/jpeg"
    }

    conn =
      conn
      |> put_req_header("x-photo-upload", "1")
      |> post(~p"/jobs/#{job.id}/photos", %{"photo" => upload})

    assert %{"ok" => true} = json_response(conn, 200)

    job = Jobs.get_job!(job.id, business.id)
    assert length(job.photos) == 1
    assert File.exists?(JobUploads.absolute_path(hd(job.photos).relative_path))
  end

  defp fixture_jpeg_path do
    Path.expand("../../support/fixtures/test-photo.jpg", __DIR__)
  end
end
