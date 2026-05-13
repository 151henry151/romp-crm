defmodule RompCrm.JobUploads do
  @moduledoc false

  @doc """
  Absolute filesystem path for a URL path stored on **`job_photos.relative_path`**
  (under **`priv/static/`**).
  """
  def absolute_path(relative) when is_binary(relative) do
    Path.join([:code.priv_dir(:romp_crm), "static", relative])
  end
end
