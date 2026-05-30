defmodule RompCrm.ContactInfoTest do
  use ExUnit.Case, async: true

  alias RompCrm.ContactInfo

  describe "normalize_email/1" do
    test "accepts common and modern-looking domains" do
      assert ContactInfo.normalize_email("pat@example.com") == {:ok, "pat@example.com"}
      assert ContactInfo.normalize_email("user@domain.eth") == {:ok, "user@domain.eth"}
    end

    test "rejects missing domain suffix" do
      assert {:error, _} = ContactInfo.normalize_email("not-an-email")
      assert {:error, _} = ContactInfo.normalize_email("missing@tld")
    end

    test "allows blank" do
      assert ContactInfo.normalize_email("") == {:ok, nil}
      assert ContactInfo.normalize_email(nil) == {:ok, nil}
    end
  end

  describe "normalize_phone/1" do
    test "normalizes NANP numbers to E.164" do
      assert ContactInfo.normalize_phone("8025551234") == {:ok, "+18025551234"}
      assert ContactInfo.normalize_phone("+18025551234") == {:ok, "+18025551234"}
    end

    test "rejects invalid NANP numbers" do
      assert {:error, _} = ContactInfo.normalize_phone("123")
      assert {:error, _} = ContactInfo.normalize_phone("0825551234")
    end

    test "allows blank" do
      assert ContactInfo.normalize_phone("") == {:ok, nil}
    end
  end

  describe "normalize_phone/2" do
    test "combines dial code and national number" do
      assert ContactInfo.normalize_phone("44", "2079460958") == {:ok, "+442079460958"}
    end
  end

  describe "split_phone/1 and format_display/1" do
    test "splits legacy 10-digit US numbers" do
      assert ContactInfo.split_phone("3476825941") == {"1", "3476825941"}
    end

    test "formats US numbers for display" do
      assert ContactInfo.format_display("+13476825941") == "(347) 682-5941"
    end
  end
end
