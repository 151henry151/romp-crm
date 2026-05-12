defmodule RompCrm.Employees.Employee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "employees" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :user, RompCrm.Accounts.User
    has_many :time_entries, RompCrm.Employees.EmployeeTimeEntry

    field :name, :string
    field :phone, :string
    field :email, :string
    field :title, :string
    field :notes, :string

    field :can_edit_jobs, :boolean, default: false
    field :can_log_job_time, :boolean, default: true
    field :can_log_own_employee_time, :boolean, default: true
    field :can_log_employee_time_for_others, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(employee, attrs) do
    employee
    |> cast(attrs, [
      :business_id,
      :user_id,
      :name,
      :phone,
      :email,
      :title,
      :notes,
      :can_edit_jobs,
      :can_log_job_time,
      :can_log_own_employee_time,
      :can_log_employee_time_for_others
    ])
    |> validate_required([:business_id, :name])
  end
end
