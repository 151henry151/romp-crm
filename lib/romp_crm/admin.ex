defmodule RompCrm.Admin do
  @moduledoc """
  Admin-only helpers (dashboard stats, access checks).

  Admin users are listed in **`Application.get_env(:romp_crm, :admin_emails)`** (downcased emails).
  """

  import Ecto.Query

  alias RompCrm.Accounts.User
  alias RompCrm.Businesses.BusinessMembership
  alias RompCrm.Jobs.Job
  alias RompCrm.Repo

  @doc "True when **`user.email`** is in the configured admin list."
  def admin?(%User{email: email}) when is_binary(email) do
    e = email |> String.trim() |> String.downcase()
    e != "" and e in admin_emails()
  end

  def admin?(_), do: false

  @doc false
  def admin_emails do
    Application.get_env(:romp_crm, :admin_emails, ["151henry151@gmail.com"])
    |> List.wrap()
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Returns **`%{total_users: integer, by_status: %{String.t() => integer}, rows: [map]}`**.

  Each row: **`id`**, **`email`**, **`subscription_status`**, **`gift_access_until`**, **`confirmed_at`**, **`inserted_at`**, **`workspaces`**, **`jobs`**.
  """
  def dashboard_stats do
    total_users = Repo.aggregate(User, :count, :id)

    by_status =
      from(u in User,
        group_by: u.subscription_status,
        select: {u.subscription_status, count(u.id)}
      )
      |> Repo.all()
      |> Map.new()

    rows =
      from(u in User,
        left_join: m in BusinessMembership,
        on: m.user_id == u.id,
        left_join: j in Job,
        on: j.business_id == m.business_id,
        group_by: u.id,
        order_by: [desc: u.inserted_at],
        select: %{
          id: u.id,
          email: u.email,
          subscription_status: u.subscription_status,
          gift_access_until: u.gift_access_until,
          confirmed_at: u.confirmed_at,
          inserted_at: u.inserted_at,
          workspaces: count(m.id, :distinct),
          jobs: count(j.id, :distinct)
        }
      )
      |> Repo.all()

    %{total_users: total_users, by_status: by_status, rows: rows}
  end
end
