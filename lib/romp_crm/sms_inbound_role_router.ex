defmodule RompCrm.SmsInboundRoleRouter do
  @moduledoc """
  Chooses contractor CRM SMS vs client booking SMS when the sender's phone may
  match both a registered user and an active booking conversation.

  Dual-role intent is classified by **`RompCrm.Ai.SmsRoleClassifier`** (Anthropic
  in production), not keyword regexes.
  """

  require Logger

  alias RompCrm.Accounts
  alias RompCrm.Ai.SmsRoleClassifier
  alias RompCrm.Bookings
  alias RompCrm.Bookings.BookingLink
  alias RompCrm.Businesses
  alias RompCrm.ClientChats
  alias RompCrm.SmsInboundRolePrompts
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @type route ::
          {:contractor, Accounts.User.t()}
          | {:client, map()}
          | {:asked_disambiguation, String.t()}

  @doc """
  Returns how to handle a Twilio inbound SMS payload.

  `params` is the Twilio webhook body map (`"From"`, `"Body"`, …).
  """
  def route(params) when is_map(params) do
    from = params["From"] |> to_string()
    body = params["Body"] |> to_string()
    norm = Phone.normalize_us(from)
    links = if norm != "", do: Bookings.active_links_for_client_phone(norm), else: []
    user = if norm != "", do: Accounts.get_user_by_phone_normalized(norm), else: nil

    cond do
      norm == "" ->
        {:client, params}

      ClientChats.taken_over_anywhere?(norm) ->
        {:client, params}

      links == [] and is_nil(user) ->
        {:client, params}

      links == [] and not is_nil(user) ->
        {:contractor, user}

      not is_nil(user) ->
        route_dual_role(norm, body, params, user, links)

      true ->
        {:client, params}
    end
  end

  defp route_dual_role(norm, body, params, user, links) do
    case SmsInboundRolePrompts.get(norm) do
      %{} = pending ->
        resolve_pending_choice(norm, body, params, user, pending)

      nil ->
        context = %{
          dual_role: true,
          pending_prompt: false,
          business_names: Enum.map(links, &business_name_for_link/1) |> Enum.reject(&(&1 == "")),
          has_active_booking_links: true,
          has_contractor_user: true
        }

        case SmsRoleClassifier.classify(body, context) do
          {:ok, :contractor} ->
            ask_disambiguation(norm, user, links)

          {:ok, :ask} ->
            ask_disambiguation(norm, user, links)

          {:ok, :client} ->
            Logger.info(
              "SmsInboundRoleRouter: dual-role phone #{norm} classified as client booking (#{length(links)} active link(s))"
            )

            {:client, params}

          {:error, reason} ->
            Logger.warning(
              "SmsInboundRoleRouter: role classify failed phone=#{norm} reason=#{inspect(reason)}; defaulting to client"
            )

            {:client, params}
        end
    end
  end

  defp resolve_pending_choice(norm, body, params, user, pending) do
    names = SmsInboundRolePrompts.business_names(pending)

    context = %{
      dual_role: true,
      pending_prompt: true,
      business_names: names,
      has_active_booking_links: true,
      has_contractor_user: true
    }

    case SmsRoleClassifier.classify(body, context) do
      {:ok, :client} ->
        SmsInboundRolePrompts.clear(norm)
        {:client, params}

      {:ok, :contractor} ->
        SmsInboundRolePrompts.clear(norm)
        {:contractor, user}

      {:ok, :ask} ->
        reask_disambiguation(norm, names)

      {:error, _} ->
        reask_disambiguation(norm, names)
    end
  end

  defp reask_disambiguation(norm, names) do
    phrase = format_business_phrase(names)

    reply =
      "Sorry—please reply with either scheduling (#{phrase}) or Romp CRM (your jobs and clients)."

    _ = Messages.send_sms(Phone.to_e164(norm), reply)
    {:asked_disambiguation, reply}
  end

  defp ask_disambiguation(norm, user, links) do
    names =
      links
      |> Enum.map(&business_name_for_link/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    SmsInboundRolePrompts.store!(norm, user.id, names)

    scheduling_phrase = format_business_phrase(names)

    reply =
      "Can you clarify — are you texting about scheduling a job with #{scheduling_phrase}, or about managing your jobs and clients in your Romp CRM account?"

    _ = Messages.send_sms(Phone.to_e164(norm), reply)
    Logger.info("SmsInboundRoleRouter: asked dual-role disambiguation phone=#{norm} user_id=#{user.id}")

    {:asked_disambiguation, reply}
  end

  defp business_name_for_link(%BookingLink{business_id: bid}) do
    case Businesses.get_business(bid) do
      %{name: name} when is_binary(name) -> String.trim(name)
      _ -> ""
    end
  end

  defp format_business_phrase([]), do: "the business that texted you"
  defp format_business_phrase([one]), do: one
  defp format_business_phrase([a, b]), do: "#{a} or #{b}"

  defp format_business_phrase(names) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> ", or " <> last
  end
end
