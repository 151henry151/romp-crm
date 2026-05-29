defmodule RompCrm.JobUploads do
  @moduledoc false

  @doc """
  Root that acts like Phoenix `priv/static` for user-uploaded job photos.

  In production this must live outside the OTP release directory so `mix release`
  does not strand files under `lib/romp_crm-<version>/priv/static/`.
  """
  def static_dir do
    Application.get_env(:romp_crm, :job_photo_static_dir) ||
      Path.join(:code.priv_dir(:romp_crm), "static")
  end

  @doc "Filesystem directory backing URL paths under `/uploads/`."
  def uploads_dir, do: Path.join(static_dir(), "uploads")

  @doc """
  Absolute filesystem path for a URL path stored on **`job_photos.relative_path`**
  (e.g. `uploads/job-photos/...`).
  """
  def absolute_path(relative) when is_binary(relative) do
    Path.join(static_dir(), relative)
  end
end
