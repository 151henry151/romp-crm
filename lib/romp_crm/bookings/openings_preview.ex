defmodule RompCrm.Bookings.OpeningsPreview do
  @moduledoc """
  Short human-readable preview of upcoming scheduling openings for contractor SMS.
  """

  alias RompCrm.Bookings.AvailabilitySummary

  @doc """
  Returns a phrase listing concrete local appointment times from the availability
  engine, e.g. `" We have openings at Thu Jun 12 at 10:00 AM or Fri Jun 13 at 2:00 PM."`
  """
  def phrase(business_id, user_id, duration_minutes \\ 120)
      when is_integer(business_id) and is_integer(user_id) do
    business_id
    |> AvailabilitySummary.compute(user_id, duration_minutes, days: 14, max_slots: 12)
    |> Map.get(:contractor_phrase, "")
  end
end
