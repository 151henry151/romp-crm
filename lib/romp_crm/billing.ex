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
  Authenticated users must have `subscription_status == "active"` to use the CRM.
  """
  def paywall_enabled? do
    RompCrm.ApplicationConfig.subscription_paywall_enabled?()
  end

  def subscription_active?(%User{subscription_status: "active"}), do: true
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
    payer_email = subscriber_email(paypal_payload)

    cond do
      status not in ["ACTIVE", "active"] ->
        {:error, {:not_active, status}}

      payer_email == "" ->
        {:error, :missing_payer_email}

      not email_matches_user?(user.email, payer_email) ->
        {:error, :email_mismatch}

      true ->
        user
        |> Ecto.Changeset.change(
          subscription_status: "active",
          paypal_subscription_id: paypal_sub_id,
          paypal_plan_id: paypal_payload["plan_id"] || user.paypal_plan_id
        )
        |> Repo.update()
    end
  end

  @doc """
  Sync subscription by id from PayPal and activate the matching user row if appropriate.
  """
  def activate_from_paypal_subscription_id(subscription_id) when is_binary(subscription_id) do
    with {:ok, body} <- PaypalClient.get_subscription(subscription_id),
         %User{} = user <- Repo.get_by(User, paypal_subscription_id: subscription_id),
         {:ok, user} <- finalize_subscription_active(user, subscription_id, body) do
      maybe_deliver_magic_link_once(user)
      {:ok, user}
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

  defp subscriber_email(body) do
    get_in(body, ["subscriber", "email_address"]) ||
      get_in(body, ["subscriber", "email"]) || ""
  end

  defp email_matches_user?(user_email, payer_email)
       when is_binary(user_email) and is_binary(payer_email) do
    String.downcase(String.trim(user_email)) == String.downcase(String.trim(payer_email))
  end

  defp email_matches_user?(_, _), do: false

  @doc """
  Used by webhook controller to normalize PayPal headers (Plug lowercases keys).
  """
  def paypal_headers_for_verify(conn) do
    conn.req_headers
    |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)
  end
end
