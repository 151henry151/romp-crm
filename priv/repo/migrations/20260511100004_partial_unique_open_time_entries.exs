defmodule RompCrm.Repo.Migrations.PartialUniqueOpenTimeEntries do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM time_entries
    WHERE ended_at IS NULL
    AND id NOT IN (
      SELECT MIN(id)
      FROM time_entries
      WHERE ended_at IS NULL
      GROUP BY business_id, job_id
    );
    """

    create unique_index(:time_entries, [:business_id, :job_id],
             name: :time_entries_one_open_clock_per_job,
             where: "ended_at IS NULL"
           )

    execute """
    DELETE FROM employee_time_entries
    WHERE clocked_out_at IS NULL
    AND id NOT IN (
      SELECT MIN(id)
      FROM employee_time_entries
      WHERE clocked_out_at IS NULL
      GROUP BY business_id, employee_id
    );
    """

    create unique_index(:employee_time_entries, [:business_id, :employee_id],
             name: :employee_time_entries_one_open_clock_per_employee,
             where: "clocked_out_at IS NULL"
           )
  end

  def down do
    drop_if_exists unique_index(:employee_time_entries, [:business_id, :employee_id],
                     name: :employee_time_entries_one_open_clock_per_employee,
                     where: "clocked_out_at IS NULL"
                   )

    drop_if_exists unique_index(:time_entries, [:business_id, :job_id],
                     name: :time_entries_one_open_clock_per_job,
                     where: "ended_at IS NULL"
                   )
  end
end
