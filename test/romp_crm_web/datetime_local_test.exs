defmodule RompCrmWeb.DatetimeLocalTest do
  use ExUnit.Case, async: true

  alias RompCrmWeb.DatetimeLocal

  test "parse/1 treats blank as missing" do
    assert DatetimeLocal.parse(nil) == {:error, :missing}
    assert DatetimeLocal.parse("") == {:error, :missing}
    assert DatetimeLocal.parse("  \t ") == {:error, :missing}
  end

  test "parse/1 accepts datetime-local without seconds" do
    assert {:ok, ndt} = DatetimeLocal.parse("2026-05-08T14:30")
    assert ndt == ~N[2026-05-08 14:30:00]
  end

  test "parse/1 accepts space instead of T" do
    assert {:ok, ndt} = DatetimeLocal.parse("2026-05-08 09:15")
    assert ndt == ~N[2026-05-08 09:15:00]
  end

  test "parse/1 passes through when seconds already present" do
    assert {:ok, ndt} = DatetimeLocal.parse("2026-05-08T09:15:45")
    assert ndt == ~N[2026-05-08 09:15:45]
  end

  test "parse/1 returns invalid for garbage" do
    assert DatetimeLocal.parse("not-a-date") == {:error, :invalid}
  end
end
