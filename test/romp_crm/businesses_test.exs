defmodule RompCrm.BusinessesTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses
  alias RompCrm.Accounts.User

  describe "resolve_sms_business_id/1" do
    test "prefers selected_business_id over sms_business_id when both are set" do
      user = user_fixture()
      {:ok, biz_a} = Businesses.create_business(user, %{name: "Alpha"})
      {:ok, biz_b} = Businesses.create_business(user, %{name: "Beta"})

      {:ok, _} =
        Accounts.get_user!(user.id)
        |> Ecto.Changeset.change(sms_business_id: biz_a.id)
        |> Repo.update()

      assert {:ok, _} =
               Accounts.put_jobs_workspace_selection(Accounts.get_user!(user.id), biz_b.id)

      assert {:ok, biz_b.id} ==
               Businesses.resolve_sms_business_id(Accounts.get_user!(user.id))
    end

    test "uses sms_business_id when selected_business_id is unset" do
      user = user_fixture()
      {:ok, _biz_a} = Businesses.create_business(user, %{name: "Alpha"})
      {:ok, biz_b} = Businesses.create_business(user, %{name: "Beta"})

      {:ok, _} =
        Accounts.get_user!(user.id)
        |> User.profile_changeset(%{sms_business_id: biz_b.id})
        |> Repo.update()

      {:ok, _} =
        Accounts.get_user!(user.id)
        |> Ecto.Changeset.change(selected_business_id: nil)
        |> Repo.update()

      assert {:ok, biz_b.id} ==
               Businesses.resolve_sms_business_id(Accounts.get_user!(user.id))
    end

    test "returns ambiguous when multiple memberships and no selected or sms default" do
      user = user_fixture()
      {:ok, _} = Businesses.create_business(user, %{name: "Alpha"})
      {:ok, _} = Businesses.create_business(user, %{name: "Beta"})

      {:ok, _} =
        Accounts.get_user!(user.id)
        |> Ecto.Changeset.change(selected_business_id: nil, sms_business_id: nil)
        |> Repo.update()

      assert {:error, :ambiguous_sms_routing} ==
               Businesses.resolve_sms_business_id(Accounts.get_user!(user.id))
    end
  end
end
