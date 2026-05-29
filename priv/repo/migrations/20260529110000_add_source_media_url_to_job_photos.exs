defmodule RompCrm.Repo.Migrations.AddSourceMediaUrlToJobPhotos do
  use Ecto.Migration

  def change do
    alter table(:job_photos) do
      add :source_media_url, :string
    end

    create unique_index(:job_photos, [:job_id, :source_media_url],
             where: "source_media_url IS NOT NULL",
             name: :job_photos_job_id_source_media_url_unique
           )
  end
end
