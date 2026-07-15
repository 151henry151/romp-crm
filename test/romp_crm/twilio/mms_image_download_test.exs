defmodule RompCrm.Twilio.MmsImageDownloadTest do
  use ExUnit.Case, async: true

  alias RompCrm.Twilio.MmsImageDownload

  # Minimal JPEG (SOI + APP0-ish stub) and PNG signatures for sniffing.
  @jpeg_bytes <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>
  @png_bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "rest">>
  @gif_bytes <<"GIF89a", 0, 0, 0, 0>>
  @webp_bytes <<"RIFF", 0, 0, 0, 0, "WEBP", "rest">>

  test "media_type_for_body/2 prefers JPEG magic over a wrong image/png header" do
    assert MmsImageDownload.media_type_for_body(@jpeg_bytes, "image/png") == "image/jpeg"
  end

  test "media_type_for_body/2 detects PNG, GIF, and WEBP from magic bytes" do
    assert MmsImageDownload.media_type_for_body(@png_bytes, "image/jpeg") == "image/png"
    assert MmsImageDownload.media_type_for_body(@gif_bytes, "image/jpeg") == "image/gif"
    assert MmsImageDownload.media_type_for_body(@webp_bytes, "image/jpeg") == "image/webp"
  end

  test "media_type_for_body/2 falls back to Content-Type when magic is unknown" do
    assert MmsImageDownload.media_type_for_body(<<"not-an-image">>, "image/png") == "image/png"
    assert MmsImageDownload.media_type_for_body(<<"not-an-image">>, "application/octet-stream") ==
             "image/jpeg"
  end
end
