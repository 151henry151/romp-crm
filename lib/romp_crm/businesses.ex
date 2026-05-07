defmodule RompCrm.Businesses do
  @moduledoc """
  Organizations (businesses), memberships, and invitations.
  """

  import Ecto.Query
  alias RompCrm.Repo

  alias RompCrm.Accounts.User
  alias RompCrm.Businesses.{Business, BusinessInvitation, BusinessMembership}

  ## Businesses

  def get_business!(id), do: Repo.get!(Business, id)

  def get_business(id), do: Repo.get(Business, id)

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

  def create_business(%User{} = user, attrs) when is_map(attrs) do
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
        _ = RompCrm.Accounts.maybe_set_default_sms_business(user, business.id)
        business
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  @doc """
  Resolves which business inbound SMS should apply to for this user.

  Uses `user.sms_business_id` when set and valid; otherwise the sole membership;
  returns error when ambiguous (multiple memberships and no explicit SMS business).
  """
  def resolve_sms_business_id(%User{} = user) do
    memberships =
      Repo.all(
        from m in BusinessMembership,
          where: m.user_id == ^user.id,
          select: m.business_id
      )

    cond do
      memberships == [] ->
        {:error, :no_membership}

      user.sms_business_id && user.sms_business_id in memberships ->
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
            Repo.transaction(fn ->
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
            end)
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
      Repo.delete(inv)
    else
      {:error, :not_owner}
    end
  end
end
