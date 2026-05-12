defmodule RompCrm.Repo.Migrations.AddUserAndPermissionsToEmployees do
  use Ecto.Migration

  def up do
    alter table(:employees) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :can_edit_jobs, :boolean, null: false, default: false
      add :can_log_job_time, :boolean, null: false, default: true
      add :can_log_own_employee_time, :boolean, null: false, default: true
      add :can_log_employee_time_for_others, :boolean, null: false, default: false
    end

    create index(:employees, [:user_id])

    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS employees_business_id_user_id_index
    ON employees (business_id, user_id)
    WHERE user_id IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS employees_business_id_user_id_index"

    alter table(:employees) do
      remove :can_log_employee_time_for_others
      remove :can_log_own_employee_time
      remove :can_log_job_time
      remove :can_edit_jobs
      remove :user_id
    end
  end
end
