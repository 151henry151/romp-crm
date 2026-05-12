defmodule RompCrm.EmployeePermissions do
  @moduledoc """
  Effective permissions for a **`User`** in a business.

  Business **owners** have full access. **Members** use the linked **`employees`** row
  (created or updated when they accept an invitation).
  """

  alias RompCrm.Accounts.User
  alias RompCrm.Businesses
  alias RompCrm.Employees

  defstruct [
    :owner,
    :linked_employee_id,
    :can_edit_jobs,
    :can_log_job_time,
    :can_log_own_employee_time,
    :can_log_employee_time_for_others
  ]

  @type t :: %__MODULE__{
          owner: boolean(),
          linked_employee_id: integer() | nil,
          can_edit_jobs: boolean(),
          can_log_job_time: boolean(),
          can_log_own_employee_time: boolean(),
          can_log_employee_time_for_others: boolean()
        }

  @doc false
  def for(%User{} = user, business_id) when is_integer(business_id) do
    if Businesses.owner?(user, business_id) do
      linked =
        case Employees.get_employee_by_user_id(user.id, business_id) do
          nil -> nil
          e -> e.id
        end

      %__MODULE__{
        owner: true,
        linked_employee_id: linked,
        can_edit_jobs: true,
        can_log_job_time: true,
        can_log_own_employee_time: true,
        can_log_employee_time_for_others: true
      }
    else
      case Employees.get_employee_by_user_id(user.id, business_id) do
        nil ->
          %__MODULE__{
            owner: false,
            linked_employee_id: nil,
            can_edit_jobs: false,
            can_log_job_time: false,
            can_log_own_employee_time: false,
            can_log_employee_time_for_others: false
          }

        emp ->
          %__MODULE__{
            owner: false,
            linked_employee_id: emp.id,
            can_edit_jobs: emp.can_edit_jobs,
            can_log_job_time: emp.can_log_job_time,
            can_log_own_employee_time: emp.can_log_own_employee_time,
            can_log_employee_time_for_others: emp.can_log_employee_time_for_others
          }
      end
    end
  end

  def can_edit_jobs?(%__MODULE__{can_edit_jobs: v}), do: v

  def can_log_job_time?(%__MODULE__{can_log_job_time: v}), do: v

  @doc """
  True when the user has a linked roster row and may record their own workday punches
  (**clock in / clock out** on the employee timeclock).
  """
  def can_punch_own_timeclock?(%__MODULE__{linked_employee_id: nil}), do: false

  def can_punch_own_timeclock?(%__MODULE__{} = caps) do
    can_log_employee_time?(caps, caps.linked_employee_id)
  end

  def can_log_employee_time?(%__MODULE__{} = caps, employee_id)
      when is_integer(employee_id) do
    cond do
      caps.owner ->
        true

      caps.linked_employee_id == employee_id ->
        caps.can_log_own_employee_time

      true ->
        caps.can_log_employee_time_for_others
    end
  end
end
