defmodule RompCrm.Gifts do
  @moduledoc """
  Gift subscriptions: admin-created tokens emailed to recipients; redeem extends CRM access.
  """

  import Ecto.Query

  alias RompCrm.Accounts.User
  alias RompCrm.Accounts.UserNotifier
  alias RompCrm.Gifts.GiftSubscription
  alias RompCrm.Repo

  @doc "Fetch an unredeemed gift by raw token string."
  def get_gift_by_token(token) when is_binary(token) do
    t = String.trim(token)

    if t == "" do
      nil
    else
      Repo.get_by(GiftSubscription, token: t)
    end
  end

  @doc """
  Creates a gift row and emails **`recipient_email`** with **`redeem_url_fun.(token)`**.

  **`attrs`**: `recipient_email`, `duration_days`, optional `admin_message` (string).
  """
  def create_and_email(%User{} = admin, attrs, redeem_url_fun)
      when is_function(redeem_url_fun, 1) and is_map(attrs) do
    recipient = attrs |> Map.get(:recipient_email) |> normalize_email()
    days = parse_duration_days(Map.get(attrs, :duration_days))
    admin_message = attrs |> Map.get(:admin_message) |> message_trim()

    with :ok <- validate_recipient(recipient),
         :ok <- validate_days(days),
         token <- new_token(),
         {:ok, gift} <- insert_gift(admin, token, recipient, days, admin_message),
         {:ok, _} <-
           UserNotifier.deliver_gift_subscription_email(
             recipient,
             redeem_url_fun.(gift.token),
             days,
             admin_message
           ) do
      {:ok, gift}
    else
      other -> other
    end
  end

  defp validate_recipient(""), do: {:error, :invalid_recipient}
  defp validate_recipient(_), do: :ok

  defp validate_days(nil), do: {:error, :invalid_duration}
  defp validate_days(n) when is_integer(n) and n > 0 and n <= 3650, do: :ok
  defp validate_days(_), do: {:error, :invalid_duration}

  defp parse_duration_days(n) when is_integer(n), do: n

  defp parse_duration_days(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_duration_days(_), do: nil

  defp message_trim(nil), do: nil
  defp message_trim(s), do: s |> to_string() |> String.trim() |> empty_to_nil()

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(s), do: s

  defp normalize_email(email) do
    email |> to_string() |> String.trim() |> String.downcase()
  end

  defp new_token do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp insert_gift(%User{id: admin_id}, token, recipient, days, admin_message) do
    %GiftSubscription{}
    |> GiftSubscription.create_changeset(%{
      token: token,
      recipient_email: recipient,
      duration_days: days,
      admin_message: admin_message,
      created_by_user_id: admin_id
    })
    |> Repo.insert()
  end

  @doc """
  Applies a pending gift to a freshly registered (or resumable) user and marks the gift redeemed.

  Expects **`user.email`** (case-insensitive) to match the gift recipient.
  """
  def apply_after_registration(%User{} = user, token) when is_binary(token) do
    case get_gift_by_token(token) do
      nil ->
        {:error, :invalid_gift}

      %GiftSubscription{redeemed_at: %DateTime{}} ->
        {:error, :already_redeemed}

      %GiftSubscription{} = gift ->
        if normalize_email(user.email) != gift.recipient_email do
          {:error, :email_mismatch}
        else
          redeem_transaction(user, gift)
        end
    end
  end

  @doc """
  Redeem for a logged-in user (must match gift recipient email).
  """
  def redeem_for_logged_in_user(%User{} = user, token) when is_binary(token) do
    case get_gift_by_token(token) do
      nil ->
        {:error, :invalid_gift}

      %GiftSubscription{redeemed_at: %DateTime{}} ->
        {:error, :already_redeemed}

      %GiftSubscription{} = gift ->
        if normalize_email(user.email) != gift.recipient_email do
          {:error, :email_mismatch}
        else
          redeem_transaction(user, gift)
        end
    end
  end

  defp redeem_transaction(%User{} = user, %GiftSubscription{} = gift) do
    Repo.transact(fn ->
      user = Repo.get!(User, user.id)

      with {:ok, user} <- apply_gift_to_user(user, gift.duration_days),
           {:ok, _gift} <- mark_redeemed(gift, user) do
        {:ok, user}
      else
        {:error, _} = err -> err
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  defp mark_redeemed(%GiftSubscription{} = gift, %User{id: uid}) do
    now = DateTime.utc_now(:second)

    gift
    |> Ecto.Changeset.change(redeemed_at: now, redeemed_user_id: uid)
    |> Repo.update()
  end

  defp apply_gift_to_user(%User{} = user, duration_days) when is_integer(duration_days) do
    now = DateTime.utc_now(:second)

    base =
      case user.gift_access_until do
        %DateTime{} = u ->
          if DateTime.compare(u, now) == :gt, do: u, else: now

        _ ->
          now
      end

    new_until = DateTime.add(base, duration_days * 86_400, :second)

    status =
      if user.subscription_status == "invited_member" do
        "invited_member"
      else
        "active"
      end

    has_paypal? =
      is_binary(user.paypal_subscription_id) and String.trim(user.paypal_subscription_id) != ""

    paypal_attrs =
      if has_paypal? do
        %{}
      else
        %{paypal_subscription_id: nil, paypal_plan_id: nil}
      end

    attrs =
      Map.merge(
        %{subscription_status: status, gift_access_until: new_until},
        paypal_attrs
      )

    user
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  @doc "List recent gifts (newest first), limit 50."
  def list_recent_gifts do
    from(g in GiftSubscription,
      order_by: [desc: g.inserted_at],
      limit: 50,
      preload: [:created_by_user, :redeemed_user]
    )
    |> Repo.all()
  end
end
