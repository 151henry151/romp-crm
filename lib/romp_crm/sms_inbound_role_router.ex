defmodule RompCrm.SmsInboundRoleRouter do
  @moduledoc """
  Chooses contractor CRM SMS vs client booking SMS when the sender's phone may
  match both a registered user and an active booking conversation.

  Default while a booking conversation is open: treat inbound as **client**
  scheduling unless the message clearly targets contractor CRM work — then ask
  which context they mean and remember the reply.
  """

  require Logger

  alias RompCrm.Accounts
  alias RompCrm.Bookings
  alias RompCrm.Bookings.BookingLink
  alias RompCrm.Businesses
  alias RompCrm.ClientChats
  alias RompCrm.SmsInboundRolePrompts
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @contractor_intent_re ~r/\b(create\s+(a\s+)?(new\s+)?job|add\s+(a\s+)?(new\s+)?lead|delete\s+(all\s+)?(my\s+)?jobs?|clock\s+(in|out)|my\s+jobs?\b|my\s+clients?\b|remind\s+me\b|time\s+entr|employee\s+hours?|workspace\b|romp\s*crm\b)\b/i

  @scheduling_choice_re ~r/\b(schedul|appointment|booking|customer|client|service\s+call|the\s+job\s+with)\b/i
  @contractor_choice_re ~r/\b(romp\s*crm|my\s+jobs?\b|my\s+clients?\b|contractor|account|workspace|managing\s+jobs)\b/i

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
        if contractor_intent?(body) do
          ask_disambiguation(norm, user, links)
        else
          Logger.info(
            "SmsInboundRoleRouter: dual-role phone #{norm} defaulting to client booking (#{length(links)} active link(s))"
          )

          {:client, params}
        end
    end
  end

  defp resolve_pending_choice(norm, body, params, user, pending) do
    trimmed = String.trim(body)

    cond do
      scheduling_choice?(trimmed, pending) ->
        SmsInboundRolePrompts.clear(norm)
        {:client, params}

      contractor_choice?(trimmed) ->
        SmsInboundRolePrompts.clear(norm)
        {:contractor, user}

      true ->
        names = SmsInboundRolePrompts.business_names(pending) |> format_business_phrase()
        reply = "Sorry—please reply with either scheduling (#{names}) or Romp CRM (your jobs and clients)."

        _ = Messages.send_sms(Phone.to_e164(norm), reply)
        {:asked_disambiguation, reply}
    end
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

  defp contractor_intent?(body) when is_binary(body) do
    t = String.trim(body)
    t != "" and String.match?(t, @contractor_intent_re)
  end

  defp scheduling_choice?(body, pending) do
    String.match?(body, @scheduling_choice_re) or
      Enum.any?(SmsInboundRolePrompts.business_names(pending), fn name ->
        name != "" and String.contains?(String.downcase(body), String.downcase(name))
      end)
  end

  defp contractor_choice?(body) do
    String.match?(body, @contractor_choice_re)
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
