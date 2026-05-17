defmodule RompCrm.Employees.EmployeeTimeEntry do
  @moduledoc """
  Per-employee clock and lunch intervals.

  Clock and lunch fields are **naive** datetimes: interpret them as local wall-clock times for the business
  (no timezone conversion in the app).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @entry_kinds [:live_punch, :sms_punch, :manual_entry, :sms_shift]

  def entry_kinds, do: @entry_kinds

  schema "employee_time_entries" do
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :employee, RompCrm.Employees.Employee

    field :clocked_in_at, :naive_datetime
    field :clocked_out_at, :naive_datetime
    field :lunch_start_at, :naive_datetime
    field :lunch_end_at, :naive_datetime
    field :notes, :string
    field :clock_in_kind, Ecto.Enum, values: @entry_kinds
    field :clock_out_kind, Ecto.Enum, values: @entry_kinds

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :business_id,
      :employee_id,
      :clocked_in_at,
      :clocked_out_at,
      :lunch_start_at,
      :lunch_end_at,
      :notes,
      :clock_in_kind,
      :clock_out_kind
    ])
    |> validate_required([:business_id, :employee_id, :clocked_in_at])
    |> unique_constraint([:business_id, :employee_id],
      name: :employee_time_entries_one_open_clock_per_employee
    )
  end

  @doc "Worked minutes excluding lunch. nil if not yet clocked out."
  def worked_minutes(%__MODULE__{clocked_in_at: ci, clocked_out_at: co} = entry)
      when not is_nil(ci) and not is_nil(co) do
    total = NaiveDateTime.diff(co, ci) |> div(60)
    max(0, total - lunch_minutes(entry))
  end

  def worked_minutes(_), do: nil

  defp lunch_minutes(%__MODULE__{lunch_start_at: ls, lunch_end_at: le})
       when not is_nil(ls) and not is_nil(le) do
    NaiveDateTime.diff(le, ls) |> div(60)
  end

  defp lunch_minutes(_), do: 0

  @doc "Human-readable worked duration string. nil if still clocked in."
  def format_duration(entry) do
    case worked_minutes(entry) do
      nil ->
        nil

      mins ->
        h = div(mins, 60)
        m = rem(mins, 60)

        cond do
          h == 0 -> "#{m}m"
          m == 0 -> "#{h}h"
          true -> "#{h}h #{m}m"
        end
    end
  end
end
