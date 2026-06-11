defmodule RompCrm.Repo.Migrations.CreateSmsPendingBookingProposals do
  use Ecto.Migration

  def change do
    create table(:sms_pending_booking_proposals) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :phone_normalized, :string, null: false
      add :proposal_json, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sms_pending_booking_proposals, [:business_id, :phone_normalized])
  end
end
