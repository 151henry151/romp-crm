defmodule RompCrmWeb.PaypalWebhookController do
  use RompCrmWeb, :controller

  alias RompCrm.Billing
  alias RompCrm.Billing.PaypalClient

  @doc """
  PayPal notifies this URL (`POST`) for billing events after you register the webhook in the PayPal developer dashboard.
  """
  def event(conn, _params) do
    raw_body = conn.private[:raw_body] || ""

    # PayPal may retry on non-200; always return plain text/minimal responses.
    if raw_body == "" do
      send_resp(conn, 400, "")
    else
      headers_map = Billing.paypal_headers_for_verify(conn)

      cond do
        not RompCrm.ApplicationConfig.subscription_paywall_enabled?() ->
          send_resp(conn, 200, "paywall_disabled")

        PaypalClient.verify_webhook!(headers_map, raw_body) ->
          decode_and_dispatch(raw_body)
          send_resp(conn, 200, "")

        true ->
          send_resp(conn, 400, "")
      end
    end
  end

  defp decode_and_dispatch(raw) do
    case Jason.decode(raw) do
      {:ok, %{"event_type" => type, "resource" => resource}} ->
        case type do
          "BILLING.SUBSCRIPTION.ACTIVATED" ->
            Billing.handle_paypal_subscription_activated(resource)

          "BILLING.SUBSCRIPTION.CANCELLED" ->
            Billing.handle_paypal_subscription_inactive(resource)

          "BILLING.SUBSCRIPTION.SUSPENDED" ->
            Billing.handle_paypal_subscription_inactive(resource)

          "BILLING.SUBSCRIPTION.EXPIRED" ->
            Billing.handle_paypal_subscription_inactive(resource)

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end
end
