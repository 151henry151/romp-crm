defmodule RompCrm.Employees.Employee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "employees" do
    belongs_to :business, RompCrm.Businesses.Business
    has_many :time_entries, RompCrm.Employees.EmployeeTimeEntry

    field :name, :string
    field :phone, :string
    field :email, :string
    field :title, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(employee, attrs) do
    employee
    |> cast(attrs, [:business_id, :name, :phone, :email, :title, :notes])
    |> validate_required([:business_id, :name])
  end
end
