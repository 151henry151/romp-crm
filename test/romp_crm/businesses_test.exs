defmodule RompCrm.BusinessesTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Accounts
  alias RompCrm.Businesses
  alias RompCrm.Accounts.User

  describe "create_business/2" do
    test "returns cannot_create_business when may_create_business is false" do
      user = user_fixture()

      {:ok, user} =
        user
        |> Ecto.Changeset.change(may_create_business: false)
        |> Repo.update()

      assert {:error, :cannot_create_business} =
               Businesses.create_business(user, %{name: "Should not exist"})
    end

    test "returns business_limit_reached when user already owns three businesses" do
      user = user_fixture()
      assert {:ok, _} = Businesses.create_business(user, %{name: "One"})
      assert {:ok, _} = Businesses.create_business(user, %{name: "Two"})
      assert {:ok, _} = Businesses.create_business(user, %{name: "Three"})

      assert {:error, :business_limit_reached} =
               Businesses.create_business(user, %{name: "Four"})
    end
  end

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

  describe "resolve_active_business_id/3" do
    test "returns nil when businesses list is empty" do
      user = user_fixture()
      assert Businesses.resolve_active_business_id(user, [], %{}) == nil
    end

    test "prefers session current_business_id when valid" do
      user = user_fixture()
      {:ok, _biz_a} = Businesses.create_business(user, %{name: "Alpha"})
      {:ok, biz_b} = Businesses.create_business(user, %{name: "Beta"})
      businesses = Businesses.list_businesses_for_user(user)
      session = %{"current_business_id" => to_string(biz_b.id)}

      assert Businesses.resolve_active_business_id(user, businesses, session) == biz_b.id
    end

    test "falls back to first listed business when session id is not a membership" do
      user = user_fixture()
      {:ok, biz_a} = Businesses.create_business(user, %{name: "Alpha"})
      {:ok, _biz_b} = Businesses.create_business(user, %{name: "Beta"})
      businesses = Businesses.list_businesses_for_user(user)
      session = %{"current_business_id" => "99999"}

      assert Businesses.resolve_active_business_id(user, businesses, session) == biz_a.id
    end
  end
end
