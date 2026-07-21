defmodule RompCrm.JobsTest do
  use RompCrm.DataCase

  alias RompCrm.Jobs

  describe "jobs" do
    alias RompCrm.Jobs.Job

    import RompCrm.JobsFixtures

    @invalid_attrs %{
      priority: nil,
      status: nil,
      address: nil,
      client_name: nil,
      phone: nil,
      client_email: nil,
      work_description: nil,
      referred_by: nil,
      notes: nil,
      next_action: nil
    }

    test "list_jobs/1 returns jobs for the business" do
      b = business_fixture()
      job = job_fixture(%{business_id: b.id})
      other = job_fixture(%{client_name: "other client", business_id: b.id})
      listed = Jobs.list_jobs(b.id)
      assert job in listed
      assert other in listed
    end

    test "get_job!/2 returns the job with given id for that business" do
      job = job_fixture()
      assert Jobs.get_job!(job.id, job.business_id) == job
    end

    test "create_job/1 with valid data creates a job" do
      b = business_fixture()

      valid_attrs = %{
        business_id: b.id,
        priority: :high,
        status: :pending,
        address: "some address",
        client_name: "some client_name",
        phone: "+18025550101",
        client_email: "client@example.com",
        work_description: "some work_description",
        referred_by: "some referred_by",
        notes: "some notes",
        next_action: "some next_action"
      }

      assert {:ok, %Job{} = job} = Jobs.create_job(valid_attrs)
      assert job.priority == :high
      assert job.status == :pending
      assert job.address == "some address"
      assert job.client_name == "some client_name"
      assert job.phone == "+18025550101"
      assert job.client_email == "client@example.com"
      assert job.work_description == "some work_description"
      assert job.referred_by == "some referred_by"
      assert job.notes == "some notes"
      assert job.next_action == "some next_action"
    end

    test "create_job/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Jobs.create_job(@invalid_attrs)
    end

    test "create_job/1 allows blank client_name when address is present" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "",
                 "priority" => "normal",
                 "status" => "lead",
                 "address_line1" => "42 Maple St",
                 "city" => "Burlington",
                 "state" => "VT",
                 "postal_code" => "05401"
               })

      assert job.client_name == ""
      assert job.address_line1 == "42 Maple St"
    end

    test "create_job/1 allows blank client_name when work_description is present" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "priority" => "normal",
                 "status" => "lead",
                 "work_description" => "Replace kitchen faucet"
               })

      assert job.client_name == ""
      assert job.work_description == "Replace kitchen faucet"
    end

    test "create_job/1 rejects job with no identifying details" do
      b = business_fixture()

      assert {:error, cs} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "",
                 "priority" => "normal",
                 "status" => "lead"
               })

      assert {"Enter a client name or at least one other detail (address, work summary, phone, notes)",
              _} = Keyword.fetch!(cs.errors, :client_name)
    end

    test "create_job/1 ignores blank work_items rows from indexed form params" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Website photos",
                 "priority" => "normal",
                 "status" => "lead",
                 "work_items" => %{
                   "0" => %{"title" => "", "sort_order" => "0", "completed" => "false"}
                 }
               })

      assert job.work_items == []
    end

    test "create_job/1 after delete allows same client_name again" do
      b = business_fixture()

      assert {:ok, job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Website photos",
                 "priority" => "normal",
                 "status" => "lead"
               })

      assert {:ok, _} = Jobs.delete_job(job)

      assert {:ok, job2} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Website photos",
                 "priority" => "normal",
                 "status" => "lead",
                 "work_description" => "Second lead"
               })

      assert job2.id != job.id
      assert job2.client_name == "Website photos"
    end

    test "update_job/2 with valid data updates the job" do
      job = job_fixture()

      update_attrs = %{
        priority: :normal,
        status: :in_progress,
        address: "some updated address",
        client_name: "some updated client_name",
        phone: "+18025550202",
        client_email: "updated@example.com",
        work_description: "some updated work_description",
        referred_by: "some updated referred_by",
        notes: "some updated notes",
        next_action: "some next_action"
      }

      assert {:ok, %Job{} = job} = Jobs.update_job(job, update_attrs)
      assert job.priority == :normal
      assert job.status == :in_progress
      assert job.address == "some updated address"
      assert job.client_name == "some updated client_name"
      assert job.phone == "+18025550202"
      assert job.client_email == "updated@example.com"
      assert job.work_description == "some updated work_description"
      assert job.referred_by == "some updated referred_by"
      assert job.notes == "some updated notes"
      assert job.next_action == "some next_action"
    end

    test "update_job/2 appends work_items without id onto existing line items" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Celeste",
                 "priority" => "normal",
                 "status" => "pending",
                 "work_description" => "Water heater",
                 "work_items" => [
                   %{"title" => "Replace water heater"},
                   %{"title" => "Reconnect lines"}
                 ]
               })

      job = Jobs.get_job!(job.id, b.id)
      assert length(job.work_items) == 2

      assert {:ok, %Job{} = job2} =
               Jobs.update_job(job, %{
                 "work_description" => "Water heater; kitchen faucet on same visit",
                 "work_items" => [%{"title" => "Replace kitchen sink faucet"}]
               })

      job2 = Jobs.get_job!(job2.id, b.id)
      titles = Enum.map(job2.work_items, & &1.title)
      assert length(job2.work_items) == 3
      assert "Replace kitchen sink faucet" in titles
      assert "Replace water heater" in titles
      assert "Reconnect lines" in titles
      assert job2.work_description == "Water heater; kitchen faucet on same visit"
    end

    test "add_job_work_item/2 appends a new line item" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Pat",
                 "priority" => "normal",
                 "status" => "pending",
                 "work_items" => [%{"title" => "First task"}]
               })

      job = Jobs.get_job!(job.id, b.id)

      assert {:ok, {job2, wi}} = Jobs.add_job_work_item(job, %{title: "Second task"})
      assert wi.title == "Second task"
      assert length(job2.work_items) == 2
    end

    test "update_job/2 appends materials from partial list onto existing materials" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Morgan",
                 "priority" => "normal",
                 "status" => "pending",
                 "work_description" => "Rough-in",
                 "materials" => [
                   %{"quantity" => 1, "description" => "First item"},
                   %{"quantity" => 2, "description" => "Second item"}
                 ]
               })

      job = Jobs.get_job!(job.id, b.id)
      assert length(job.materials) == 2

      assert {:ok, %Job{} = job2} =
               Jobs.update_job(job, %{
                 "materials" => [%{"quantity" => 4, "description" => "Third item"}]
               })

      job2 = Jobs.get_job!(job2.id, b.id)
      assert length(job2.materials) == 3
      descs = job2.materials |> Enum.sort_by(& &1.sort_order) |> Enum.map(& &1.description)
      assert descs == ["First item", "Second item", "Third item"]

      third = Enum.find(job2.materials, &(&1.description == "Third item"))
      assert third.quantity == 4.0
    end

    test "update_job/2 zip-merges work_items without id when count matches (SMS date edits, no duplicate)" do
      b = business_fixture()

      assert {:ok, %Job{} = job} =
               Jobs.create_job(%{
                 "business_id" => b.id,
                 "client_name" => "Paul",
                 "priority" => "normal",
                 "status" => "in_progress",
                 "work_description" => "Bath rough-in",
                 "work_items" => [
                   %{"title" => "Sink stops"},
                   %{"title" => "Sink drain"}
                 ]
               })

      job = Jobs.get_job!(job.id, b.id)
      assert length(job.work_items) == 2
      [wi1, wi2] = Enum.sort_by(job.work_items, &{&1.sort_order, &1.id})

      assert {:ok, %Job{} = job2} =
               Jobs.update_job(job, %{
                 "work_items" => [
                   %{"title" => wi1.title, "scheduled_on" => "2026-05-15"},
                   %{"title" => wi2.title, "scheduled_on" => "2026-05-19"}
                 ]
               })

      job2 = Jobs.get_job!(job2.id, b.id)
      assert length(job2.work_items) == 2
      titles = job2.work_items |> Enum.sort_by(& &1.id) |> Enum.map(& &1.title)
      assert titles == ["Sink stops", "Sink drain"]

      by_title = Map.new(job2.work_items, &{&1.title, &1})
      assert Date.compare(by_title["Sink stops"].scheduled_on, ~D[2026-05-15]) == :eq
      assert Date.compare(by_title["Sink drain"].scheduled_on, ~D[2026-05-19]) == :eq
    end

    test "delete_job/1 deletes the job" do
      job = job_fixture()
      assert {:ok, %Job{}} = Jobs.delete_job(job)

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(job.id, job.business_id)
      end
    end

    test "change_job/2 returns a job changeset" do
      job = job_fixture()
      assert %Ecto.Changeset{} = Jobs.change_job(job)
    end

    test "change_job/2 treats duplicate billing checkbox params as checked" do
      job = job_fixture()

      changeset =
        Jobs.change_job(job, %{
          "billing_address_different" => ["false", "true"]
        })

      assert Ecto.Changeset.get_change(changeset, :billing_address_different) == true
    end

    test "change_job/2 validates phone and email formats" do
      job = job_fixture()

      phone_changeset = Jobs.change_job(job, %{"phone" => "not-a-phone"})
      assert {"Enter a valid phone number for the selected country", _} = Keyword.fetch!(phone_changeset.errors, :phone)

      email_changeset = Jobs.change_job(job, %{"client_email" => "bad-email"})
      assert {"Enter a valid email address (name@domain.tld)", _} = Keyword.fetch!(email_changeset.errors, :client_email)
    end

    test "find_job_for_sms_update/2 returns job when match hints uniquely" do
      b = business_fixture()

      j =
        job_fixture(%{
          business_id: b.id,
          client_name: "Angela Brande",
          address: "old",
          work_description: "line repair"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(%{"client_name" => "Angela Brande"}, b.id)

      assert got.id == j.id
    end

    test "find_job_for_sms_update/2 returns :ambiguous when two jobs tie closely" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Same Client Dup", address: "1 A St"})
      job_fixture(%{business_id: b.id, client_name: "Same Client Dup", address: "2 B St"})

      assert {:error, :ambiguous} =
               Jobs.find_job_for_sms_update(%{"client_name" => "Same Client Dup"}, b.id)
    end

    test "find_job_for_sms_update/2 disambiguates duplicate names with address_snippet" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Dup Name", address: "100 Oak Ave"})
      target = job_fixture(%{business_id: b.id, client_name: "Dup Name", address: "200 Pine Rd"})

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(
                 %{
                   "client_name" => "Dup Name",
                   "address_snippet" => "200 Pine"
                 },
                 b.id
               )

      assert got.id == target.id
    end

    test "find_job_for_sms_update/2 returns :no_match when nothing scores enough" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Someone Else"})

      assert {:error, :no_match} =
               Jobs.find_job_for_sms_update(%{"client_name" => "ZZZ Nonexistent Person"}, b.id)
    end

    test "find_job_for_sms_update/2 matches by work_description_snippet when it is the only strong hint" do
      b = business_fixture()

      j =
        job_fixture(%{
          business_id: b.id,
          client_name: "Bud Reed",
          address: "Evergreen Lane",
          work_description: "Water shutoff"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(
                 %{"work_description_snippet" => "water shutoff"},
                 b.id
               )

      assert got.id == j.id
    end

    test "find_job_for_sms_update/2 returns :ambiguous when two jobs share the same work phrase" do
      b = business_fixture()
      job_fixture(%{business_id: b.id, client_name: "Ann", work_description: "Water shutoff"})
      job_fixture(%{business_id: b.id, client_name: "Bob", work_description: "Water shutoff"})

      assert {:error, :ambiguous} =
               Jobs.find_job_for_sms_update(
                 %{"work_description_snippet" => "water shutoff"},
                 b.id
               )
    end

    test "snapshot_for_sms_ai/1 includes client_email when set" do
      b = business_fixture()

      job_fixture(%{
        business_id: b.id,
        client_name: "Email Client",
        client_email: "pat@example.com"
      })

      [row] = Jobs.snapshot_for_sms_ai(b.id)
      assert row["client_email"] == "pat@example.com"
    end

    test "find_job_for_sms_update/2 accepts address_snippet alone when exactly one job matches" do
      b = business_fixture()

      j =
        job_fixture(%{
          business_id: b.id,
          client_name: "Corner Case",
          address: "999 Zephyr Road"
        })

      assert {:ok, got} =
               Jobs.find_job_for_sms_update(%{"address_snippet" => "Zephyr"}, b.id)

      assert got.id == j.id
    end

    test "add_job_photo skips duplicate source_media_url on same job" do
      b = business_fixture()
      job = job_fixture(%{business_id: b.id})
      bytes = :crypto.strong_rand_bytes(64)

      assert {:ok, _} =
               Jobs.add_job_photo(job, b.id, bytes, "image/jpeg", nil,
                 source_media_url: "https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME1"
               )

      assert {:ok, :duplicate_skipped} =
               Jobs.add_job_photo(job, b.id, bytes, "image/jpeg", nil,
                 source_media_url: "https://api.twilio.com/2010-04-01/Accounts/AC/Media/ME1"
               )
    end

    test "delete_job_photo removes row and file" do
      prev = Application.get_env(:romp_crm, :job_photo_static_dir)
      dir = Path.join(System.tmp_dir!(), "romp-crm-photo-delete-test-#{System.unique_integer()}")
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

      b = business_fixture()
      job = job_fixture(%{business_id: b.id})
      bytes = :crypto.strong_rand_bytes(64)

      assert {:ok, photo} = Jobs.add_job_photo(job, b.id, bytes, "image/jpeg")
      abs = RompCrm.JobUploads.absolute_path(photo.relative_path)
      assert File.exists?(abs)

      assert {:ok, _} = Jobs.delete_job_photo(job, b.id, photo.id)
      refute File.exists?(abs)
      refute Repo.get(RompCrm.Jobs.JobPhoto, photo.id)
    end

    test "move_job_photo swaps gallery order" do
      b = business_fixture()
      job = job_fixture(%{business_id: b.id})

      assert {:ok, a} = Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(8), "image/jpeg")
      assert {:ok, b_row} = Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(8), "image/jpeg")

      assert {:ok, _} = Jobs.move_job_photo(job, b.id, b_row.id, :up)

      job = Jobs.get_job!(job.id, b.id)
      ids = Enum.map(job.photos, & &1.id)
      assert ids == [b_row.id, a.id]
    end

    test "sort_job_photos_by_timestamp orders oldest to newest" do
      prev = Application.get_env(:romp_crm, :job_photo_static_dir)
      dir = Path.join(System.tmp_dir!(), "romp-crm-photo-sort-ts-#{System.unique_integer()}")
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

      b = business_fixture()
      job = job_fixture(%{business_id: b.id})

      assert {:ok, newest} = Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(8), "image/jpeg")
      assert {:ok, oldest} = Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(8), "image/jpeg")
      assert {:ok, middle} = Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(8), "image/jpeg")

      t0 = ~U[2024-01-01 10:00:00Z]
      t1 = ~U[2024-01-02 10:00:00Z]
      t2 = ~U[2024-01-03 10:00:00Z]

      {:ok, _} =
        newest
        |> Ecto.Changeset.change(inserted_at: t2, updated_at: t2)
        |> Repo.update()

      {:ok, _} =
        oldest
        |> Ecto.Changeset.change(inserted_at: t0, updated_at: t0)
        |> Repo.update()

      {:ok, _} =
        middle
        |> Ecto.Changeset.change(inserted_at: t1, updated_at: t1)
        |> Repo.update()

      assert {:ok, updated} = Jobs.sort_job_photos_by_timestamp(job, b.id)
      ids = Enum.map(updated.photos, & &1.id)
      assert ids == [oldest.id, middle.id, newest.id]
      assert Enum.map(updated.photos, & &1.sort_order) == [0, 1, 2]
    end

    test "delete_all_job_photos removes all rows and files" do
      prev = Application.get_env(:romp_crm, :job_photo_static_dir)
      dir = Path.join(System.tmp_dir!(), "romp-crm-photo-delete-all-#{System.unique_integer()}")
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

      b = business_fixture()
      job = job_fixture(%{business_id: b.id})

      assert {:ok, a} = Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(64), "image/jpeg")
      assert {:ok, b_row} =
               Jobs.add_job_photo(job, b.id, :crypto.strong_rand_bytes(64), "image/jpeg")
      abs_a = RompCrm.JobUploads.absolute_path(a.relative_path)
      abs_b = RompCrm.JobUploads.absolute_path(b_row.relative_path)
      assert File.exists?(abs_a)
      assert File.exists?(abs_b)

      assert {:ok, updated, 2} = Jobs.delete_all_job_photos(job, b.id)
      refute File.exists?(abs_a)
      refute File.exists?(abs_b)
      assert updated.photos == []
      refute Repo.get(RompCrm.Jobs.JobPhoto, a.id)
      refute Repo.get(RompCrm.Jobs.JobPhoto, b_row.id)
    end
  end
end
