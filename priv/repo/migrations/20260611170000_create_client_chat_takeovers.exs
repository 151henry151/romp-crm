defmodule RompCrm.Repo.Migrations.CreateClientChatTakeovers do
  use Ecto.Migration

  def change do
    create table(:client_chat_takeovers) do
      add :business_id, references(:businesses, on_delete: :delete_all), null: false
      add :booking_link_id, references(:booking_links, on_delete: :nilify_all)
      add :phone_normalized, :string, null: false
      add :taken_over_by_user_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:client_chat_takeovers, [:business_id, :phone_normalized])
    create index(:client_chat_takeovers, [:booking_link_id])
  end
end
