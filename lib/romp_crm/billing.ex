defmodule RompCrm.Billing do
  @moduledoc """
  Paywall and PayPal subscription helpers.
  """

  import Ecto.Query

  alias RompCrm.Accounts
  alias RompCrm.Accounts.User
  alias RompCrm.Billing.PaypalClient
  alias RompCrm.Repo

  @plan_keys ~w(monthly annual)

  @doc """
  When true, new sign-ups start as `pending_payment` and must complete PayPal before the magic link is sent.
  Authenticated users need **`subscription_status`** **`active`** or **`invited_member`**, or an unexpired **`gift_access_until`**, when the paywall is enabled.
  """
  def paywall_enabled? do
    RompCrm.ApplicationConfig.subscription_paywall_enabled?()
  end

  def subscription_active?(%User{subscription_status: status})
      when status in ["active", "invited_member"],
      do: true

  def subscription_active?(%User{} = user) do
    case user.gift_access_until do
      %DateTime{} = until ->
        DateTime.compare(DateTime.utc_now(:second), until) == :lt

      _ ->
        false
    end
  end

  def subscription_active?(_), do: false

  @doc """
  Valid plan query/form values: `monthly` | `annual`.
  """
  def valid_plan?(plan) when plan in @plan_keys, do: true
  def valid_plan?(_), do: false

  @doc """
  Resolves configured PayPal billing plan id for the given plan key.
  """
  def paypal_plan_id("monthly"), do: Application.get_env(:romp_crm, :paypal_plan_monthly_id)
  def paypal_plan_id("annual"), do: Application.get_env(:romp_crm, :paypal_plan_annual_id)
  def paypal_plan_id(_), do: nil

  def plan_configured?(plan) do
    case paypal_plan_id(plan) do
      s when is_binary(s) and byte_size(s) > 0 -> true
      _ -> false
    end
  end

  @doc """
  Free-trial length in days (matches **`PAYPAL_TRIAL_DAYS`** / provisioned PayPal plan cycles).
  """
  def paypal_trial_days do
    Application.get_env(:romp_crm, :paypal_trial_days, 14)
  end

  @doc """
  After creating a PayPal subscription, associate the approval-pending id and chosen plan on the user row.
  """
  def put_pending_paypal_subscription(%User{} = user, subscription_id, plan_key)
      when is_binary(subscription_id) do
    plan_id = paypal_plan_id(plan_key)

    user
    |> Ecto.Changeset.change(
      paypal_subscription_id: subscription_id,
      paypal_plan_id: plan_id,
      subscription_status: "pending_payment"
    )
    |> Repo.update()
  end

  @doc """
  Starts PayPal hosted approval for the user; returns the external `approve_url`.
  """
  def start_paypal_checkout(%User{} = user, plan_key, return_url_fun, cancel_url_fun)
      when is_function(return_url_fun, 0) and is_function(cancel_url_fun, 0) do
    with true <- paywall_enabled?(),
         true <- valid_plan?(plan_key),
         true <- plan_configured?(plan_key),
         plan_id when is_binary(plan_id) <- paypal_plan_id(plan_key),
         {:ok, %{id: sub_id, approve_url: approve}} <-
           PaypalClient.create_subscription(
             plan_id,
             return_url_fun.(),
             cancel_url_fun.(),
             user
           ),
         {:ok, user} <- put_pending_paypal_subscription(user, sub_id, plan_key) do
      {:ok, %{user: user, approve_url: approve}}
    else
      false -> {:error, :misconfigured}
      {:error, _} = err -> err
      _ -> {:error, :misconfigured}
    end
  end

  @doc """
  Called from PayPal return URL or webhooks once the billing agreement should be usable.
  """
  def finalize_subscription_active(%User{} = user, paypal_sub_id, paypal_payload)
      when is_binary(paypal_sub_id) and is_map(paypal_payload) do
    status = paypal_payload["status"]
    plan_id = paypal_plan_id_from_payload(paypal_payload, user)

    cond do
      not subscription_usable_status?(status) ->
        {:error, {:not_active, status}}

      true ->
        user
        |> Ecto.Changeset.change(
          subscription_status: "active",
          paypal_subscription_id: paypal_sub_id,
          paypal_plan_id: plan_id
        )
        |> Repo.update()
    end
  end

  defp subscription_usable_status?(status) when status in [nil, ""] do
    false
  end

  defp subscription_usable_status?(status) do
    String.upcase(to_string(status)) in ["ACTIVE", "APPROVED"]
  end

  defp paypal_plan_id_from_payload(paypal_payload, %User{} = user) do
    paypal_payload["plan_id"] ||
      get_in(paypal_payload, ["plan", "id"]) ||
      user.paypal_plan_id
  end

  @doc """
  Reads subscription id from PayPal's browser return URL (query string).

  PayPal may send **`subscription_id`**, **`subscriptionId`**, or (less often) **`token`** when it matches subscription id shape (**`I-…`**).
  """
  def paypal_return_subscription_id(params) when is_map(params) do
    direct =
      (params["subscription_id"] || params["subscriptionId"] || "")
      |> to_string()
      |> String.trim()

    if direct != "" do
      direct
    else
      token =
        (params["token"] || params["ba_token"] || "")
        |> to_string()
        |> String.trim()

      if token != "" and paypal_subscription_id_shape?(token) do
        token
      else
        ""
      end
    end
  end

  defp paypal_subscription_id_shape?(id) when is_binary(id) do
    String.match?(id, ~r/^I-[A-Z0-9]+$/i)
  end

  @doc """
  Sync subscription by id from PayPal and activate the matching user row if appropriate.
  """
  def activate_from_paypal_subscription_id(subscription_id) when is_binary(subscription_id) do
    case PaypalClient.get_subscription(subscription_id) do
      {:error, reason} ->
        {:error, {:paypal_subscription_fetch, reason}}

      {:ok, body} ->
        case Repo.get_by(User, paypal_subscription_id: subscription_id) do
          nil ->
            {:error, :unknown_subscription}

          user ->
            case finalize_subscription_active(user, subscription_id, body) do
              {:ok, user} ->
                maybe_deliver_magic_link_once(user)
                {:ok, user}

              {:error, _} = err ->
                err
            end
        end
    end
  end

  defp magic_link_login_url(token) do
    RompCrmWeb.Endpoint.url()
    |> String.trim_trailing("/")
    |> Kernel.<>(RompCrmWeb.Endpoint.path("/users/log-in/#{token}"))
  end

  defp maybe_deliver_magic_link_once(%User{confirmed_at: nil} = user) do
    {:ok, _} = Accounts.deliver_login_instructions(user, &magic_link_login_url/1)
    :ok
  end

  defp maybe_deliver_magic_link_once(%User{}), do: :ok

  def handle_paypal_subscription_activated(resource) when is_map(resource) do
    id = resource["id"]

    if is_binary(id) do
      _ = activate_from_paypal_subscription_id(id)
    end

    :ok
  end

  def handle_paypal_subscription_inactive(resource) when is_map(resource) do
    id = resource["id"]

    if is_binary(id) do
      from(u in User,
        where: u.paypal_subscription_id == ^id
      )
      |> Repo.update_all(set: [subscription_status: "inactive"])
    end

    :ok
  end

  @doc """
  Cancels the signed-in subscriber's PayPal billing subscription and marks the user **`inactive`** locally.

  Only available when the hosted paywall is enabled and the account is a paying **`active`** subscriber with a stored
  **`paypal_subscription_id`** (not **`invited_member`**).

  On success, clears PayPal ids on the user row so they match webhook **`CANCELLED`** handling.
  """
  def cancel_subscription_for_user(%User{} = user) do
    cond do
      not paywall_enabled?() ->
        {:error, :not_cancellable}

      user.subscription_status != "active" ->
        {:error, :not_cancellable}

      not is_binary(user.paypal_subscription_id) or String.trim(user.paypal_subscription_id) == "" ->
        {:error, :not_cancellable}

      true ->
        sub_id = String.trim(user.paypal_subscription_id)

        case PaypalClient.cancel_subscription(sub_id, "Customer cancelled via Romp CRM settings") do
          {:ok, _} ->
            user
            |> Ecto.Changeset.change(
              subscription_status: "inactive",
              paypal_subscription_id: nil,
              paypal_plan_id: nil
            )
            |> Repo.update()

          {:error, reason} ->
            {:error, {:paypal_cancel_failed, reason}}
        end
    end
  end

  @doc """
  Used by webhook controller to normalize PayPal headers (Plug lowercases keys).
  """
  def paypal_headers_for_verify(conn) do
    conn.req_headers
    |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)
  end
end
