defmodule RompCrm.Businesses do
  @moduledoc """
  Organizations (businesses), memberships, and invitations.
  """

  import Ecto.Query
  alias RompCrm.Repo

  alias RompCrm.Accounts.User
  alias RompCrm.BusinessAuditLogs
  alias RompCrm.Businesses.{Business, BusinessInvitation, BusinessMembership}
  alias RompCrm.Employees

  @max_owned_businesses_per_account 3

  @default_first_workspace_name "My workspace"

  @doc """
  Maximum businesses one account may create (`owner` memberships). Invited team members do not consume this quota.
  """
  def owned_business_creation_limit, do: @max_owned_businesses_per_account

  ## Businesses

  def get_business!(id), do: Repo.get!(Business, id)

  def get_business(id), do: Repo.get(Business, id)

  @doc """
  Lists businesses the user owns (**`role` `:owner`** only).
  """
  def list_owned_businesses_for_user(%User{} = user) do
    Repo.all(
      from b in Business,
        join: m in BusinessMembership,
        on: m.business_id == b.id,
        where: m.user_id == ^user.id and m.role == ^:owner,
        order_by: [asc: b.name],
        select: b
    )
  end

  @doc """
  Lists businesses the user belongs to.
  """
  def list_businesses_for_user(%User{} = user) do
    Repo.all(
      from b in Business,
        join: m in BusinessMembership,
        on: m.business_id == b.id,
        where: m.user_id == ^user.id,
        order_by: [asc: b.name],
        select: b
    )
  end

  @doc """
  Ensures **`user`** has at least one workspace when they may create businesses.

  When **`list_businesses_for_user/1`** is empty and **`User.may_create_business?/1`** is true,
  creates a business named **`My workspace`** (same rules as **`create_business/2`**) so Jobs and
  the first-login SMS intro never hit an empty scope. Invited-only accounts (**`may_create_business`**
  false) are unchanged.

  Returns **`{:ok, businesses}`** or **`create_business/2`** errors.
  """
  def ensure_default_workspace_if_empty(%User{} = user) do
    businesses = list_businesses_for_user(user)

    cond do
      businesses != [] ->
        {:ok, businesses}

      not User.may_create_business?(user) ->
        {:ok, []}

      true ->
        case create_business(user, %{name: @default_first_workspace_name}) do
          {:ok, _} ->
            {:ok, list_businesses_for_user(user)}

          {:error, _} = err ->
            err
        end
    end
  end

  @doc """
  Resolves the active workspace **`business_id`** for **`user`**, matching
  **`RompCrmWeb.UserAuth.on_mount(:ensure_business_scope)`** rules.

  Uses **`session["current_business_id"]`** when it matches a membership, then
  **`user.selected_business_id`**, then the first row in **`businesses`**.

  Returns **`nil`** when **`businesses`** is empty.
  """
  def resolve_active_business_id(%User{} = user, businesses, session)
      when is_list(businesses) and is_map(session) do
    case businesses do
      [] -> nil
      _ -> do_resolve_active_business_id(user, businesses, session)
    end
  end

  defp do_resolve_active_business_id(%User{} = user, businesses, session) do
    allowed = MapSet.new(Enum.map(businesses, & &1.id))

    session_business_id =
      parse_session_business_id(
        Map.get(session, "current_business_id") || Map.get(session, :current_business_id)
      )

    persisted_id = user.selected_business_id

    cond do
      session_business_id && MapSet.member?(allowed, session_business_id) ->
        session_business_id

      persisted_id && MapSet.member?(allowed, persisted_id) ->
        persisted_id

      true ->
        hd(businesses).id
    end
  end

  defp parse_session_business_id(nil), do: nil
  defp parse_session_business_id(id) when is_integer(id), do: id

  defp parse_session_business_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, _} -> n
      :error -> nil
    end
  end

  def member?(%User{id: uid}, business_id) when is_integer(business_id) do
    Repo.exists?(
      from m in BusinessMembership,
        where: m.user_id == ^uid and m.business_id == ^business_id
    )
  end

  def owner?(%User{id: uid}, business_id) when is_integer(business_id) do
    Repo.exists?(
      from m in BusinessMembership,
        where: m.user_id == ^uid and m.business_id == ^business_id and m.role == ^:owner
    )
  end

  def create_business(%User{may_create_business: false}, _attrs) do
    {:error, :cannot_create_business}
  end

  def create_business(%User{} = user, attrs) when is_map(attrs) do
    if owned_business_count(user) >= @max_owned_businesses_per_account do
      {:error, :business_limit_reached}
    else
      create_business_transaction(user, attrs)
    end
  end

  defp create_business_transaction(%User{} = user, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, business} <-
             %Business{}
             |> Business.changeset(attrs)
             |> Repo.insert(),
           {:ok, _mem} <-
             %BusinessMembership{}
             |> BusinessMembership.changeset(%{
               business_id: business.id,
               user_id: user.id,
               role: :owner
             })
             |> Repo.insert() do
        # Reload so `sms_business_id` reflects the DB (avoid stale struct overwriting default).
        _ =
          RompCrm.Accounts.maybe_set_default_sms_business(Repo.get!(User, user.id), business.id)

        business
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  defp owned_business_count(%User{id: uid}) do
    Repo.one(
      from m in BusinessMembership,
        where: m.user_id == ^uid and m.role == :owner,
        select: count(m.id)
    )
  end

  @doc """
  Resolves which business inbound SMS should apply to for this user.

  Priority:

  1. **`user.selected_business_id`** — matches the Jobs workspace / header picker (updated when the user switches businesses or accepts an invite).
  2. **`user.sms_business_id`** — optional override from **Settings → SMS workspace** when several memberships exist and no picker selection is stored.
  3. **Sole membership** — only one business.
  4. **`ambiguous_sms_routing`** — multiple memberships and neither (1) nor (2) resolves.

  The webhook identifies the texter by normalizing Twilio **`From`** and looking up **`users.phone_normalized`**.
  """
  def resolve_sms_business_id(%User{} = user) do
    memberships =
      Repo.all(
        from m in BusinessMembership,
          where: m.user_id == ^user.id,
          select: m.business_id
      )

    membership_set = MapSet.new(memberships)

    cond do
      memberships == [] ->
        {:error, :no_membership}

      user.selected_business_id &&
          MapSet.member?(membership_set, user.selected_business_id) ->
        {:ok, user.selected_business_id}

      user.sms_business_id && MapSet.member?(membership_set, user.sms_business_id) ->
        {:ok, user.sms_business_id}

      length(memberships) == 1 ->
        {:ok, hd(memberships)}

      true ->
        {:error, :ambiguous_sms_routing}
    end
  end

  ## Invitations

  def invite_user(%Business{} = business, %User{} = inviter, email)
      when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    cond do
      not owner?(inviter, business.id) ->
        {:error, :not_owner}

      true ->
        case Repo.get_by(User, email: email) do
          %User{} = u ->
            if member?(u, business.id) do
              {:error, :already_member}
            else
              insert_invitation_and_mail(business, inviter, email)
            end

          nil ->
            insert_invitation_and_mail(business, inviter, email)
        end
    end
  end

  defp insert_invitation_and_mail(%Business{} = business, %User{} = inviter, email) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = BusinessInvitation.hash_raw_token(raw_token)

    attrs = %{
      business_id: business.id,
      invited_by_user_id: inviter.id,
      email: email,
      token_hash: token_hash
    }

    case %BusinessInvitation{}
         |> BusinessInvitation.changeset(attrs)
         |> Repo.insert() do
      {:ok, invitation} ->
        case Employees.ensure_placeholder_for_invitation(business.id, email, inviter.id) do
          {:ok, :created, emp} ->
            BusinessAuditLogs.record(%{
              business_id: business.id,
              actor_user_id: inviter.id,
              source: "web",
              action: "employees.create",
              entity_type: "employees",
              entity_id: emp.id,
              metadata: %{reason: "invitation_placeholder"}
            })

          _ ->
            :ok
        end

        BusinessAuditLogs.record(%{
          business_id: business.id,
          actor_user_id: inviter.id,
          source: "web",
          action: "business_invitation.create",
          entity_type: "business_invitations",
          entity_id: invitation.id,
          metadata: %{email: email}
        })

        url = invitation_accept_url(raw_token)
        _ = RompCrm.Businesses.Notifier.deliver_invitation(invitation, business, url)
        {:ok, invitation}

      {:error, %Ecto.Changeset{} = cs} ->
        {:error, cs}
    end
  end

  # `RompCrmWeb.Endpoint.url/0` has no path component; the mount (`/romp-crm`, etc.)
  # belongs in `RompCrmWeb.Endpoint.path/1`. See Phoenix endpoint callbacks.
  defp invitation_accept_url(raw_token) do
    RompCrmWeb.Endpoint.url()
    |> String.trim_trailing("/")
    |> Kernel.<>(RompCrmWeb.Endpoint.path("/invitations/#{raw_token}"))
  end

  def get_invitation_by_raw_token(raw) when is_binary(raw) do
    hash = BusinessInvitation.hash_raw_token(raw)
    lookup_invitation(hash)
  end

  defp lookup_invitation(token_hash) do
    Repo.one(
      from i in BusinessInvitation,
        where: i.token_hash == ^token_hash
    )
    |> invitation_expired?()
  end

  defp invitation_expired?(nil), do: nil

  defp invitation_expired?(%BusinessInvitation{} = inv) do
    days = BusinessInvitation.token_validity_in_days()
    exp = DateTime.add(inv.inserted_at, days, :day)

    if DateTime.after?(DateTime.utc_now(:second), exp) do
      nil
    else
      inv
    end
  end

  def accept_invitation_raw(raw_token, %User{} = user) when is_binary(raw_token) do
    case get_invitation_by_raw_token(raw_token) do
      nil ->
        {:error, :invalid_or_expired}

      %BusinessInvitation{} = inv ->
        case invitation_email_matches?(inv, user) do
          {:error, _} = e ->
            e

          :ok ->
            case Repo.transaction(fn ->
                   cs =
                     %BusinessMembership{}
                     |> BusinessMembership.changeset(%{
                       business_id: inv.business_id,
                       user_id: user.id,
                       role: :member
                     })

                   case Repo.insert(cs) do
                     {:ok, _} ->
                       :ok

                     {:error, changeset} ->
                       if duplicate_membership_constraint?(changeset) do
                         :ok
                       else
                         Repo.rollback(changeset)
                       end
                   end

                   Repo.delete!(inv)
                   get_business!(inv.business_id)
                 end) do
              {:ok, business} ->
                _ = Employees.link_user_after_invite_accept(business.id, user)

                BusinessAuditLogs.record(%{
                  business_id: business.id,
                  actor_user_id: user.id,
                  source: "web",
                  action: "business_membership.create",
                  entity_type: "businesses",
                  entity_id: business.id,
                  metadata: %{role: "member", via: "invitation_accept"}
                })

                {:ok, business}

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  defp invitation_email_matches?(inv, user) do
    if String.downcase(String.trim(inv.email)) == String.downcase(String.trim(user.email)) do
      :ok
    else
      {:error, :email_mismatch}
    end
  end

  defp duplicate_membership_constraint?(%Ecto.Changeset{} = cs) do
    Enum.any?(cs.errors, fn {_field, {_msg, opts}} -> opts[:constraint] == :unique end)
  end

  def list_pending_invitations(%Business{} = business) do
    Repo.all(
      from i in BusinessInvitation,
        where: i.business_id == ^business.id,
        order_by: [desc: i.inserted_at]
    )
  end

  def cancel_invitation(%User{} = user, invitation_id) when is_integer(invitation_id) do
    inv = Repo.get!(BusinessInvitation, invitation_id)

    if owner?(user, inv.business_id) do
      bid = inv.business_id
      iid = inv.id

      case Repo.delete(inv) do
        {:ok, _} ->
          BusinessAuditLogs.record(%{
            business_id: bid,
            actor_user_id: user.id,
            source: "web",
            action: "business_invitation.cancel",
            entity_type: "business_invitations",
            entity_id: iid,
            metadata: %{}
          })

          {:ok, :deleted}

        {:error, _} = err ->
          err
      end
    else
      {:error, :not_owner}
    end
  end
end
