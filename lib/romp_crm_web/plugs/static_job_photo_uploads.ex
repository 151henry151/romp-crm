defmodule RompCrmWeb.Plugs.StaticJobPhotoUploads do
  @moduledoc false
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    opts =
      Plug.Static.init(
        at: "/uploads",
        from: RompCrm.JobUploads.uploads_dir(),
        gzip: false,
        raise_on_missing_only: false
      )

    Plug.Static.call(conn, opts)
  end
end
