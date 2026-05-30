defmodule RompCrm.Repo.Migrations.AddStructuredAddressesToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :address_line1, :string
      add :address_line2, :string
      add :city, :string
      add :state, :string
      add :postal_code, :string

      add :billing_address_different, :boolean, null: false, default: false
      add :billing_address_line1, :string
      add :billing_address_line2, :string
      add :billing_city, :string
      add :billing_state, :string
      add :billing_postal_code, :string
    end

    execute(
      """
      UPDATE jobs
      SET address_line1 = address
      WHERE address IS NOT NULL AND trim(address) != ''
      """,
      ""
    )
  end
end
