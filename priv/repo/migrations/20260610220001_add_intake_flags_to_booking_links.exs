defmodule RompCrm.Repo.Migrations.AddIntakeFlagsToBookingLinks do
  use Ecto.Migration

  def change do
    alter table(:booking_links) do
      add :intake_flags_json, :text
    end
  end
end
