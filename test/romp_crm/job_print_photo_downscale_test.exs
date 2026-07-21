defmodule RompCrm.JobPrintPhotoDownscaleTest do
  use ExUnit.Case, async: true

  alias RompCrm.JobPrint

  setup do
    dir = Path.join(System.tmp_dir!(), "romp-job-print-downscale-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "prepare_photo_for_pdf returns a smaller jpeg for oversized originals", %{dir: dir} do
    src = Path.join(dir, "big.jpg")

    {_, 0} =
      System.cmd(
        "convert",
        [
          "-size",
          "2400x1800",
          "plasma:fractal",
          "-quality",
          "95",
          src
        ],
        stderr_to_stdout: true
      )

    original = File.read!(src)
    assert byte_size(original) > 180_000

    assert {"image/jpeg", prepared} = JobPrint.prepare_photo_for_pdf(src, "image/jpeg")
    assert byte_size(prepared) < byte_size(original)
    assert <<0xFF, 0xD8, _::binary>> = prepared
  end

  test "prepare_photo_for_pdf keeps small images as-is when already compact", %{dir: dir} do
    src = Path.join(dir, "tiny.jpg")

    {_, 0} =
      System.cmd(
        "convert",
        ["-size", "40x30", "xc:red", "-quality", "80", src],
        stderr_to_stdout: true
      )

    original = File.read!(src)
    assert {"image/jpeg", prepared} = JobPrint.prepare_photo_for_pdf(src, "image/jpeg")
    assert prepared == original
  end
end
