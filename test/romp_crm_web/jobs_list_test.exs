defmodule RompCrmWeb.JobsListTest do
  use RompCrm.DataCase, async: true

  alias RompCrm.Jobs.Job
  alias RompCrm.Jobs.JobWorkItem
  alias RompCrmWeb.JobsList

  describe "effective_schedule_date/1" do
    test "uses job scheduled_on when no work items" do
      job = %Job{scheduled_on: ~D[2026-06-10]}
      assert JobsList.effective_schedule_date(job) == ~D[2026-06-10]
    end

    test "uses soonest work item date when earlier than job date" do
      job = %Job{
        scheduled_on: ~D[2026-06-10],
        work_items: [
          %JobWorkItem{scheduled_on: ~D[2026-06-03]},
          %JobWorkItem{scheduled_on: ~D[2026-06-15]}
        ]
      }

      assert JobsList.effective_schedule_date(job) == ~D[2026-06-03]
    end

    test "returns nil when no dates" do
      assert JobsList.effective_schedule_date(%Job{}) == nil
    end
  end

  describe "sort_jobs/2" do
    test "sorts alphabetically by client name" do
      jobs = [
        %Job{id: 1, client_name: "Zed"},
        %Job{id: 2, client_name: "Amy"}
      ]

      assert Enum.map(JobsList.sort_jobs(jobs, :name), & &1.id) == [2, 1]
    end

    test "sorts by scheduled date with undated jobs last" do
      jobs = [
        %Job{id: 1, client_name: "A", scheduled_on: ~D[2026-06-20]},
        %Job{id: 2, client_name: "B"},
        %Job{id: 3, client_name: "C", scheduled_on: ~D[2026-06-05]}
      ]

      assert Enum.map(JobsList.sort_jobs(jobs, :scheduled), & &1.id) == [3, 1, 2]
    end

    test "sorts by creation date newest first" do
      jobs = [
        %Job{id: 1, client_name: "A", inserted_at: ~U[2026-01-01 12:00:00Z]},
        %Job{id: 2, client_name: "B", inserted_at: ~U[2026-02-01 12:00:00Z]}
      ]

      assert Enum.map(JobsList.sort_jobs(jobs, :created), & &1.id) == [2, 1]
    end
  end

  describe "filter_active?/1" do
    test "is false for all jobs" do
      refute JobsList.filter_active?(:all)
    end

    test "is true for a status filter" do
      assert JobsList.filter_active?(:lead)
      assert JobsList.filter_active?(:in_progress)
    end
  end

  describe "filter_button_label/1" do
    test "notes when a filter is active" do
      assert JobsList.filter_button_label(:all) == "Filter: All jobs"
      assert JobsList.filter_button_label(:lead) =~ "Filter active: Lead"
      assert JobsList.filter_button_label(:lead) =~ "not all jobs"
    end

    test "notes when color-code is enabled" do
      assert JobsList.filter_button_label(:all, true) =~ "Color-code on"
    end
  end

  describe "status_badge_class/2" do
    test "returns distinct greyscale shades when color-code is off" do
      lead = JobsList.status_badge_class(:lead, false)
      pending = JobsList.status_badge_class(:pending, false)
      in_progress = JobsList.status_badge_class(:in_progress, false)
      done = JobsList.status_badge_class(:done, false)

      assert lead != pending
      assert pending != in_progress
      assert in_progress != done
      assert lead =~ "base-"
      assert done =~ "base-300"
    end

    test "returns status colors when color-code is on" do
      assert JobsList.status_badge_class(:lead, true) =~ "blue"
      assert JobsList.status_badge_class(:pending, true) =~ "amber"
      assert JobsList.status_badge_class(:in_progress, true) =~ "green"
    end
  end

  describe "priority_badge_class/2" do
    test "returns distinct greyscale for high priority when color-code is off" do
      assert JobsList.priority_badge_class(:high, false) =~ "border-base-content"
    end

    test "returns red for high priority when color-code is on" do
      assert JobsList.priority_badge_class(:high, true) =~ "red"
    end
  end

  describe "mobile_card_classes/2" do
    test "uses a lighter surface for high-priority collapsed cards" do
      job = %Job{priority: :high}
      normal = %Job{priority: :normal}

      assert JobsList.mobile_card_classes(job, false) =~ "bg-base-200"
      assert JobsList.mobile_card_classes(normal, false) =~ "bg-base-100"
      refute JobsList.mobile_card_classes(normal, false) =~ "shadow-sm"
      assert JobsList.mobile_card_classes(job, false) =~ "shadow-sm"
    end
  end

  describe "primary_heading/2" do
    test "shows address when address-primary mode is on" do
      job = %Job{client_name: "Amy", address: "42 Maple St"}
      assert JobsList.primary_heading(job, true) == "42 Maple St"
      assert JobsList.secondary_heading(job, true) == "Amy"
    end
  end
end
