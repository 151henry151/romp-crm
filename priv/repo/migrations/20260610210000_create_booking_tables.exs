defmodule RompCrm.Repo.Migrations.CreateBookingTables do
  use Ecto.Migration

  def change do
    create table(:booking_links) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :technician_user_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, references(:clients, on_delete: :nilify_all)
      add :job_id, references(:jobs, on_delete: :nilify_all)

      add :token, :string, null: false
      add :job_type_label, :string, null: false, default: ""
      add :duration_min_minutes, :integer, null: false, default: 60
      add :duration_max_minutes, :integer, null: false, default: 120
      add :client_phone_normalized, :string
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:booking_links, [:token])
    create index(:booking_links, [:business_id])
    create index(:booking_links, [:client_phone_normalized, :status])

    create table(:bookings) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :technician_user_id, references(:users, on_delete: :delete_all), null: false
      add :booking_link_id, references(:booking_links, on_delete: :nilify_all)
      add :client_id, references(:clients, on_delete: :nilify_all)
      add :job_id, references(:jobs, on_delete: :nilify_all)

      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "confirmed"
      add :confirmed_via, :string, null: false, default: "web"

      timestamps(type: :utc_datetime)
    end

    create index(:bookings, [:business_id])
    create index(:bookings, [:technician_user_id, :status, :starts_at])

    create table(:booking_requests) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :technician_user_id, references(:users, on_delete: :delete_all), null: false
      add :booking_link_id, references(:booking_links, on_delete: :nilify_all)
      add :client_id, references(:clients, on_delete: :nilify_all)

      add :availability_text, :text, null: false, default: ""
      add :parsed_windows_json, :text
      add :job_type_label, :string, null: false, default: ""
      add :duration_min_minutes, :integer
      add :duration_max_minutes, :integer
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:booking_requests, [:business_id, :status])
    create index(:booking_requests, [:technician_user_id, :status])
  end
end
