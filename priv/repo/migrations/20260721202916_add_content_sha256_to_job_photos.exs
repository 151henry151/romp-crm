defmodule RompCrm.Repo.Migrations.AddContentSha256ToJobPhotos do
  use Ecto.Migration

  def change do
    alter table(:job_photos) do
      add :content_sha256, :string, size: 64
    end

    create index(:job_photos, [:job_id, :content_sha256])
  end
end
