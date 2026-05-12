defmodule RompCrm.EmployeePermissionsTest do
  use RompCrm.DataCase, async: false

  alias RompCrm.AccountsFixtures
  alias RompCrm.Businesses
  alias RompCrm.Businesses.BusinessMembership
  alias RompCrm.EmployeePermissions
  alias RompCrm.Employees
  alias RompCrm.Repo

  test "owner has all capabilities" do
    user = AccountsFixtures.user_fixture()
    {:ok, biz} = Businesses.create_business(user, %{name: "Co"})

    caps = EmployeePermissions.for(user, biz.id)
    assert caps.owner
    assert EmployeePermissions.can_edit_jobs?(caps)
    assert EmployeePermissions.can_log_job_time?(caps)
    assert EmployeePermissions.can_log_employee_time?(caps, 999)
  end

  test "member follows employee row flags" do
    owner = AccountsFixtures.user_fixture()
    {:ok, biz} = Businesses.create_business(owner, %{name: "Co"})
    member = AccountsFixtures.user_fixture()

    {:ok, _} =
      %BusinessMembership{}
      |> BusinessMembership.changeset(%{
        business_id: biz.id,
        user_id: member.id,
        role: :member
      })
      |> Repo.insert()

    {:ok, emp} =
      Employees.create_employee(%{
        "business_id" => biz.id,
        "name" => "Member",
        "email" => member.email,
        "user_id" => member.id,
        "can_edit_jobs" => false,
        "can_log_job_time" => true,
        "can_log_own_employee_time" => true,
        "can_log_employee_time_for_others" => false
      })

    caps = EmployeePermissions.for(member, biz.id)
    refute caps.owner
    refute EmployeePermissions.can_edit_jobs?(caps)
    assert EmployeePermissions.can_log_job_time?(caps)
    assert EmployeePermissions.can_log_employee_time?(caps, emp.id)
    refute EmployeePermissions.can_log_employee_time?(caps, emp.id + 1)
  end
end
