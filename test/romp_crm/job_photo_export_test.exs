defmodule RompCrm.JobPhotoExportTest do
  use RompCrm.DataCase

  import RompCrm.JobsFixtures

  alias RompCrm.JobPhotoExport
  alias RompCrm.JobUploads
  alias RompCrm.Jobs

  setup do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)
    dir = Path.join(System.tmp_dir!(), "romp-crm-photo-export-test-#{System.unique_integer()}")
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

  test "build_job_photos_zip includes files in a job folder" do
    b = business_fixture()
    job = job_fixture(%{business_id: b.id, client_name: "Acme / Site"})
    bytes = :crypto.strong_rand_bytes(64)

    assert {:ok, _} = Jobs.add_job_photo(job, b.id, bytes, "image/jpeg")
    job = Jobs.get_job!(job.id, b.id)

    assert {:ok, zip} = JobPhotoExport.build_job_photos_zip(job)
    assert byte_size(zip) > 0

    tmp = Path.join(System.tmp_dir!(), "romp-crm-export-unzip-#{System.unique_integer()}")
    File.mkdir_p!(tmp)
    zip_path = Path.join(tmp, "job.zip")
    File.write!(zip_path, zip)

    on_exit(fn -> File.rm_rf(tmp) end)

    assert {:ok, file_list} = :zip.list_dir(String.to_charlist(zip_path))
    joined = zip_entry_names(file_list)
    assert joined =~ "job-#{job.id} - Acme Site/"
    assert joined =~ "001-photo-"
  end

  test "build_all_photos_zip groups photos by job" do
    b = business_fixture()
    job_a = job_fixture(%{business_id: b.id, client_name: "Alpha"})
    job_b = job_fixture(%{business_id: b.id, client_name: "Beta"})
    bytes = :crypto.strong_rand_bytes(32)

    assert {:ok, _} = Jobs.add_job_photo(job_a, b.id, bytes, "image/jpeg")
    assert {:ok, _} = Jobs.add_job_photo(job_b, b.id, bytes, "image/jpeg")

    assert {:ok, zip} = JobPhotoExport.build_all_photos_zip([b.id])
    assert byte_size(zip) > 0

    tmp = Path.join(System.tmp_dir!(), "romp-crm-export-all-#{System.unique_integer()}")
    File.mkdir_p!(tmp)
    zip_path = Path.join(tmp, "all.zip")
    File.write!(zip_path, zip)

    on_exit(fn -> File.rm_rf(tmp) end)

    assert {:ok, file_list} = :zip.list_dir(String.to_charlist(zip_path))
    joined = zip_entry_names(file_list)
    assert joined =~ "job-#{job_a.id} - Alpha/"
    assert joined =~ "job-#{job_b.id} - Beta/"
  end

  test "build_all_photos_zip returns no_photos when empty" do
    b = business_fixture()
    _job = job_fixture(%{business_id: b.id})
    assert {:error, :no_photos} = JobPhotoExport.build_all_photos_zip([b.id])
  end

  test "photo_download_filename uses stored basename" do
    b = business_fixture()
    job = job_fixture(%{business_id: b.id})
    {:ok, photo} = Jobs.add_job_photo(job, b.id, <<1, 2, 3>>, "image/jpeg")
    name = JobPhotoExport.photo_download_filename(photo)
    assert name =~ "job-photo-#{photo.id}-"
    assert name =~ Path.basename(photo.relative_path)
    assert File.exists?(JobUploads.absolute_path(photo.relative_path))
  end

  defp zip_entry_names(file_list) do
    names = for {:zip_file, name, _, _, _, _} <- file_list, do: List.to_string(name)
    Enum.join(names, "\n")
  end
end
