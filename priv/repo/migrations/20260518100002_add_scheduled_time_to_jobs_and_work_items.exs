defmodule RompCrm.Repo.Migrations.AddScheduledTimeToJobsAndWorkItems do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :scheduled_time, :time
    end

    alter table(:job_work_items) do
      add :scheduled_time, :time
    end
  end
end
