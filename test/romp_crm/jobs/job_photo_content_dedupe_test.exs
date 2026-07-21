defmodule RompCrm.Jobs.JobPhotoContentDedupeTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.Jobs
  alias RompCrm.Jobs.JobPhoto
  alias RompCrm.JobUploads
  alias RompCrm.Repo

  import RompCrm.JobsFixtures

  setup do
    prev = Application.get_env(:romp_crm, :job_photo_static_dir)
    dir = Path.join(System.tmp_dir!(), "romp-crm-photo-dedupe-#{System.unique_integer()}")
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

    business = business_fixture()
    job = job_fixture(%{business_id: business.id})
    %{business: business, job: job}
  end

  test "skips exact byte-identical image on the same job", %{business: business, job: job} do
    bytes = :crypto.strong_rand_bytes(128)

    assert {:ok, photo} = Jobs.add_job_photo(job, business.id, bytes, "image/jpeg")
    assert is_binary(photo.content_sha256)
    assert String.length(photo.content_sha256) == 64

    assert {:ok, :duplicate_skipped} =
             Jobs.add_job_photo(job, business.id, bytes, "image/jpeg")

    job = Jobs.get_job!(job.id, business.id)
    assert length(job.photos) == 1
  end

  test "allows the same image bytes on a different job", %{business: business, job: job} do
    other = job_fixture(%{business_id: business.id, client_name: "Other Client"})
    bytes = :crypto.strong_rand_bytes(96)

    assert {:ok, _} = Jobs.add_job_photo(job, business.id, bytes, "image/jpeg")
    assert {:ok, _} = Jobs.add_job_photo(other, business.id, bytes, "image/jpeg")
  end

  test "allows different image bytes on the same job", %{business: business, job: job} do
    assert {:ok, _} = Jobs.add_job_photo(job, business.id, :crypto.strong_rand_bytes(32), "image/jpeg")
    assert {:ok, _} = Jobs.add_job_photo(job, business.id, :crypto.strong_rand_bytes(32), "image/jpeg")

    job = Jobs.get_job!(job.id, business.id)
    assert length(job.photos) == 2
  end

  test "purge_duplicate_photos_for_job/2 keeps one file per content hash", %{
    business: business,
    job: job
  } do
    bytes_a = :crypto.strong_rand_bytes(40)
    bytes_b = :crypto.strong_rand_bytes(40)

    # Bypass content dedupe by inserting a second copy with the same hash after first upload
    assert {:ok, first} = Jobs.add_job_photo(job, business.id, bytes_a, "image/jpeg")
    assert {:ok, _} = Jobs.add_job_photo(job, business.id, bytes_b, "image/jpeg")

    # Force a duplicate row for bytes_a (simulates pre-dedupe data)
    rel = "uploads/job-photos/#{business.id}/#{job.id}/forced-dup.jpg"
    abs = JobUploads.absolute_path(rel)
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, bytes_a)

    {:ok, _} =
      %JobPhoto{}
      |> JobPhoto.changeset(%{
        job_id: job.id,
        relative_path: rel,
        content_type: "image/jpeg",
        byte_size: byte_size(bytes_a),
        content_sha256: first.content_sha256,
        sort_order: 99
      })
      |> Repo.insert()

    assert {:ok, removed} = Jobs.purge_duplicate_photos_for_job(job, business.id)
    assert removed == 1

    job = Jobs.get_job!(job.id, business.id)
    assert length(job.photos) == 2
    assert Enum.count(job.photos, &(&1.content_sha256 == first.content_sha256)) == 1
  end
end
