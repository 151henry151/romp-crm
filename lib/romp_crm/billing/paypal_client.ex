defmodule RompCrm.Billing.PaypalClient do
  @moduledoc """
  Thin PayPal REST client (OAuth + Subscriptions + webhook verification).

  Loads configuration from `:romp_crm` Application env (`:paypal_*` keys).
  """

  alias RompCrm.Accounts.User

  @finch RompCrm.Finch

  @spec base_url :: String.t()
  def base_url do
    mode = Application.get_env(:romp_crm, :paypal_mode, "sandbox")

    if mode == "live" do
      "https://api-m.paypal.com"
    else
      "https://api-m.sandbox.paypal.com"
    end
  end

  @spec access_token :: {:ok, String.t()} | {:error, term()}
  def access_token do
    id = Application.get_env(:romp_crm, :paypal_client_id)
    secret = Application.get_env(:romp_crm, :paypal_client_secret)

    unless is_binary(id) and byte_size(id) > 0 and is_binary(secret) and byte_size(secret) > 0 do
      {:error, :missing_paypal_credentials}
    else
      basic = Base.encode64("#{id}:#{secret}")

      case Req.post("#{base_url()}/v1/oauth2/token",
             headers: [
               {"authorization", "Basic #{basic}"},
               {"content-type", "application/x-www-form-urlencoded"}
             ],
             body: URI.encode_query(%{"grant_type" => "client_credentials"}),
             finch: @finch,
             retry: false
           ) do
        {:ok, %{status: 200, body: %{"access_token" => tok}}} ->
          {:ok, tok}

        {:ok, %{status: s, body: b}} ->
          {:error, {:oauth, s, b}}

        {:error, _} = e ->
          e
      end
    end
  end

  @doc """
  Creates a subscription in `APPROVAL_PENDING` state and returns the `approve` link href.
  """
  @spec create_subscription(String.t(), String.t(), String.t(), User.t()) ::
          {:ok, %{id: String.t(), approve_url: String.t()}} | {:error, term()}
  def create_subscription(plan_id, return_url, cancel_url, %User{} = user) do
    with {:ok, tok} <- access_token() do
      body = %{
        "plan_id" => plan_id,
        "custom_id" => "user:#{user.id}",
        "subscriber" => %{
          "email_address" => user.email
        },
        "application_context" => %{
          "brand_name" => Application.get_env(:romp_crm, :paypal_brand_name, "Romp CRM"),
          "locale" => "en-US",
          "shipping_preference" => "NO_SHIPPING",
          "user_action" => "SUBSCRIBE_NOW",
          "return_url" => return_url,
          "cancel_url" => cancel_url
        }
      }

      case Req.post("#{base_url()}/v1/billing/subscriptions",
             headers: [
               {"authorization", "Bearer #{tok}"},
               {"content-type", "application/json"},
               {"prefer", "return=representation"}
             ],
             json: body,
             finch: @finch,
             retry: false
           ) do
        {:ok, %{status: status, body: resp}} when status in [200, 201] ->
          id = resp["id"]
          approve = link_href(resp["links"], "approve")

          if is_binary(id) and is_binary(approve) do
            {:ok, %{id: id, approve_url: approve}}
          else
            {:error, {:create_subscription, :missing_id_or_approve, resp}}
          end

        {:ok, %{status: s, body: b}} ->
          {:error, {:create_subscription, s, b}}

        {:error, _} = e ->
          e
      end
    end
  end

  @doc """
  Fetches subscription details (status, subscriber email, plan id).
  """
  @spec get_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  def get_subscription(subscription_id) when is_binary(subscription_id) do
    with {:ok, tok} <- access_token() do
      case Req.get("#{base_url()}/v1/billing/subscriptions/#{subscription_id}",
             headers: [{"authorization", "Bearer #{tok}"}],
             finch: @finch,
             retry: false
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: s, body: b}} ->
          {:error, {:get_subscription, s, b}}

        {:error, _} = e ->
          e
      end
    end
  end

  @doc """
  Cancels an active PayPal billing subscription (**`/v1/billing/subscriptions/{id}/cancel`**).

  Returns **`{:ok, :cancelled}`** on HTTP **204**. If PayPal responds with an error but the subscription is already
  terminated (**`CANCELLED`** / **`EXPIRED`**), returns **`{:ok, :already_cancelled}`**.
  """
  @spec cancel_subscription(String.t(), String.t()) :: {:ok, :cancelled | :already_cancelled} | {:error, term()}
  def cancel_subscription(subscription_id, reason \\ "Customer requested cancellation")
      when is_binary(subscription_id) and is_binary(reason) do
    trimmed_reason =
      reason
      |> String.trim()
      |> then(fn r ->
        if r == "", do: "Customer requested cancellation", else: String.slice(r, 0, 127)
      end)

    with {:ok, tok} <- access_token() do
      url = "#{base_url()}/v1/billing/subscriptions/#{subscription_id}/cancel"

      case Req.post(url,
             headers: [
               {"authorization", "Bearer #{tok}"},
               {"content-type", "application/json"}
             ],
             json: %{"reason" => trimmed_reason},
             finch: @finch,
             retry: false
           ) do
        {:ok, %{status: 204}} ->
          {:ok, :cancelled}

        {:ok, %{status: s, body: body}} when s in [400, 404, 422] ->
          case subscription_already_inactive?(
                 subscription_id,
                 body
               ) do
            true -> {:ok, :already_cancelled}
            false -> {:error, {:cancel_subscription, s, body}}
          end

        {:ok, %{status: s, body: b}} ->
          {:error, {:cancel_subscription, s, b}}

        {:error, _} = e ->
          e
      end
    end
  end

  defp subscription_already_inactive?(subscription_id, error_body) do
    text =
      case error_body do
        %{} = m -> Jason.encode!(m)
        bin when is_binary(bin) -> bin
        nil -> ""
        other -> inspect(other)
      end

    body_hint_inactive?(text) or subscription_status_inactive?(subscription_id)
  end

  defp body_hint_inactive?(text) when is_binary(text) do
    t = String.downcase(text)

    String.contains?(t, "already cancelled") or String.contains?(t, "already canceled") or
      String.contains?(t, "subscription has been cancelled") or
      String.contains?(t, "subscription has been canceled") or
      String.contains?(t, "status invalid") or String.contains?(t, "not active")
  end

  defp subscription_status_inactive?(subscription_id) do
    case get_subscription(subscription_id) do
      {:ok, %{"status" => st}} when is_binary(st) ->
        String.upcase(st) in ["CANCELLED", "CANCELED", "EXPIRED", "SUSPENDED"]

      _ ->
        false
    end
  end

  @doc """
  Verifies a webhook using PayPal's `/v1/notifications/verify-webhook-signature` API.
  `raw_body` must be the exact JSON string PayPal posted.
  """
  @spec verify_webhook!(map(), String.t()) :: boolean()
  def verify_webhook!(headers, raw_body) when is_map(headers) and is_binary(raw_body) do
    if Application.get_env(:romp_crm, :paypal_skip_webhook_verify, false) do
      true
    else
      webhook_id = Application.get_env(:romp_crm, :paypal_webhook_id)

      unless is_binary(webhook_id) and byte_size(webhook_id) > 0 do
        false
      else
        event = Jason.decode!(raw_body)

        payload = %{
          "transmission_id" => header_one(headers, "paypal-transmission-id"),
          "transmission_time" => header_one(headers, "paypal-transmission-time"),
          "cert_url" => header_one(headers, "paypal-cert-url"),
          "auth_algo" => header_one(headers, "paypal-auth-algo"),
          "transmission_sig" => header_one(headers, "paypal-transmission-sig"),
          "webhook_id" => webhook_id,
          "webhook_event" => event
        }

        case access_token() do
          {:ok, tok} ->
            case Req.post("#{base_url()}/v1/notifications/verify-webhook-signature",
                   headers: [
                     {"authorization", "Bearer #{tok}"},
                     {"content-type", "application/json"}
                   ],
                   json: payload,
                   finch: @finch,
                   retry: false
                 ) do
              {:ok, %{status: 200, body: %{"verification_status" => "SUCCESS"}}} ->
                true

              _ ->
                false
            end

          {:error, _} ->
            false
        end
      end
    end
  end

  defp header_one(headers, key) do
    case Map.get(headers, key) do
      [h | _] -> h
      h when is_binary(h) -> h
      _ -> ""
    end
  end

  defp link_href(links, rel) when is_list(links) do
    case Enum.find(links, &(&1["rel"] == rel)) do
      %{"href" => url} -> url
      _ -> nil
    end
  end

  defp link_href(_, _), do: nil
end
