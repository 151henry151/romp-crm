defmodule RompCrm.JobUploadsTest do
  use ExUnit.Case, async: true

  alias RompCrm.JobUploads

  test "absolute_path joins configured static dir" do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)

    try do
      Application.put_env(:romp_crm, :job_photo_static_dir, "/tmp/romp-crm-static-test")

      assert JobUploads.absolute_path("uploads/job-photos/1/2/x.jpg") ==
               "/tmp/romp-crm-static-test/uploads/job-photos/1/2/x.jpg"

      assert JobUploads.uploads_dir() == "/tmp/romp-crm-static-test/uploads"
    after
      if prev do
        Application.put_env(:romp_crm, :job_photo_static_dir, prev)
      else
        Application.delete_env(:romp_crm, :job_photo_static_dir)
      end
    end
  end
end
