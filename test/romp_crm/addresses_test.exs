defmodule RompCrm.AddressesTest do
  use ExUnit.Case, async: true

  alias RompCrm.Addresses
  alias RompCrm.Jobs.Job

  test "format_service/1 uses structured fields" do
    job = %Job{
      address_line1: "42 Maple St",
      city: "Burlington",
      state: "VT",
      postal_code: "05401"
    }

    assert Addresses.format_service(job) == "42 Maple St, Burlington, VT 05401"
  end

  test "format_service/1 falls back to legacy address" do
    job = %Job{address: "99 Oak Ave"}
    assert Addresses.format_service(job) == "99 Oak Ave"
  end

  test "parse_us_address/1 splits comma-separated legacy addresses" do
    assert Addresses.parse_us_address("South St, Middlebury VT") == %{
             "address_line1" => "South St",
             "address_line2" => nil,
             "city" => "Middlebury",
             "state" => "VT",
             "postal_code" => nil
           }
  end

  test "enrich_ai_address_update/2 merges partial street with existing legacy address" do
    job = %Job{
      address: "South St, Middlebury VT",
      address_line1: nil,
      city: nil,
      state: nil
    }

    attrs = Addresses.enrich_ai_address_update(job, %{"address" => "5 south st"})

    assert attrs["address_line1"] == "5 South St"
    assert attrs["city"] == "Middlebury"
    assert attrs["state"] == "VT"
    assert attrs["address"] == "5 South St, Middlebury, VT"
  end

  test "enrich_ai_address_update/2 keeps structured snapshot city when AI sends street only" do
    job = %Job{
      address_line1: "South St",
      city: "Middlebury",
      state: "VT",
      postal_code: "05753"
    }

    attrs = Addresses.enrich_ai_address_update(job, %{"address_line1" => "5 south st"})

    assert attrs["address_line1"] == "5 South St"
    assert attrs["city"] == "Middlebury"
    assert attrs["state"] == "VT"
    assert attrs["postal_code"] == "05753"
  end

  test "merge_ai_address_attrs/1 splits flat address into line1" do
    assert Addresses.merge_ai_address_attrs(%{"address" => "123 Main St"})["address_line1"] ==
             "123 Main St"
  end

  test "merge_ai_address_attrs/1 parses billing_address when flagged" do
    attrs =
      Addresses.merge_ai_address_attrs(%{
        "billing_address_different" => true,
        "billing_address" => "PO Box 12"
      })

    assert attrs["billing_address_different"] == true
    assert attrs["billing_address_line1"] == "PO Box 12"
  end

  test "atom_job_address_attrs_if_present/1 skips when no address keys" do
    assert Addresses.atom_job_address_attrs_if_present(%{"phone" => "555-1212"}) == %{}
  end

  test "same_address?/2 compares normalized parts" do
    a = %{"address_line1" => "42 Maple", "city" => "Burlington", "state" => "vt"}
    b = %{"address_line1" => "42 maple", "city" => "Burlington", "state" => "VT"}

    assert Addresses.same_address?(a, b)
  end
end
