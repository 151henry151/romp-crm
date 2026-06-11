defmodule RompCrm.Scheduling.SlotApprovals do
  @moduledoc """
  When `confirm_before_offer_slots` is enabled, customer-facing slot offers are
  held until the contractor approves via SMS.
  """

  import Ecto.Query

  alias RompCrm.Bookings.BookingLink
  alias RompCrm.Repo
  alias RompCrm.Scheduling.SlotApproval
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @yes_re ~r/^(yes|y|ok|okay|sure|go ahead|approve|send|do it)\b/i

  def pending_for_technician?(business_id, user_id) when is_integer(business_id) do
    Repo.exists?(
      from a in SlotApproval,
        where:
          a.business_id == ^business_id and a.technician_user_id == ^user_id and
            a.status == "pending"
    )
  end

  def get_pending(business_id, user_id) do
    Repo.one(
      from a in SlotApproval,
        where:
          a.business_id == ^business_id and a.technician_user_id == ^user_id and
            a.status == "pending",
        order_by: [desc: a.id],
        limit: 1,
        preload: [:booking_link]
    )
  end

  def approved_offerings_for_link(link_id) when is_integer(link_id) do
    case Repo.one(
           from a in SlotApproval,
             where: a.booking_link_id == ^link_id and a.status == "approved",
             order_by: [desc: a.id],
             limit: 1
         ) do
      nil ->
        []

      %SlotApproval{local_offerings_json: json} ->
        case Jason.decode(json) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end
    end
  end

  @doc "Creates a pending approval and texts the contractor."
  def request!(%BookingLink{} = link, local_offerings, open_slots, customer_reply) do
    link = Repo.preload(link, [:client, :technician_user])

    offerings_json = Jason.encode!(local_offerings)
    slots_json = if open_slots, do: Jason.encode!(open_slots), else: nil

    approval =
      %SlotApproval{}
      |> SlotApproval.changeset(%{
        business_id: link.business_id,
        technician_user_id: link.technician_user_id,
        booking_link_id: link.id,
        client_phone_normalized: link.client_phone_normalized,
        local_offerings_json: offerings_json,
        open_slots_json: slots_json,
        customer_pending_reply: customer_reply,
        status: "pending"
      })
      |> Repo.insert!()

    contractor_phone = link.technician_user && link.technician_user.phone

    if is_binary(contractor_phone) and contractor_phone != "" do
      client_name =
        (link.client && link.client.client_name) || "the customer"

      job = link.job_type_label || "the job"
      times = format_times(local_offerings)

      msg =
        "Scheduling #{job} for #{client_name} — I have #{times} available. " <>
          "Reply YES to offer these times to them, or text me different instructions."

      _ = Messages.send_sms(contractor_phone, msg)
    end

    approval
  end

  @doc "Contractor replied to a slot approval prompt."
  def handle_contractor_reply(user_id, business_id, body) do
    case get_pending(business_id, user_id) do
      nil ->
        :none

      %SlotApproval{} = approval ->
        if String.match?(String.trim(body), @yes_re) do
          approve_and_notify_customer!(approval)
        else
          reject!(approval)
          {:rejected, "OK — I won't offer those times. Tell me how you'd like to proceed with that customer."}
        end
    end
  end

  defp approve_and_notify_customer!(%SlotApproval{} = approval) do
    approval =
      approval
      |> SlotApproval.changeset(%{status: "approved"})
      |> Repo.update!()

    offerings =
      case Jason.decode(approval.local_offerings_json) do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    link = Repo.get!(BookingLink, approval.booking_link_id) |> Repo.preload(:client)
    phone_e164 = Phone.to_e164(approval.client_phone_normalized)

    customer_msg =
      build_customer_offer_message(link, offerings, approval.customer_pending_reply)

    if phone_e164 do
      _ = Messages.send_sms(phone_e164, customer_msg)
    end

    {:approved, "Offered #{format_times(offerings)} to #{client_label(link)}."}
  end

  defp reject!(approval) do
    approval
    |> SlotApproval.changeset(%{status: "rejected"})
    |> Repo.update!()
  end

  defp build_customer_offer_message(link, offerings, _pending_reply) do
    name =
      link.client && link.client.client_name
      |> case do
        n when is_binary(n) ->
          n |> String.split(" ") |> List.first()

        _ ->
          nil
      end

    greeting = if name, do: "Hi #{name},", else: "Hi,"

    times = format_times(offerings)

    "#{greeting} thanks for your patience — we have #{times} available for your #{link.job_type_label || "visit"}. " <>
      "Do any of those work, or let us know another time that suits you?"
  end

  defp client_label(%BookingLink{client: %{client_name: name}}) when is_binary(name), do: name
  defp client_label(_), do: "the customer"

  defp format_times([one]), do: one

  defp format_times([a, b]) do
    "#{a} or #{b}"
  end

  defp format_times(times) do
    {rest, [last]} = Enum.split(times, -1)
    Enum.join(rest, ", ") <> ", or " <> last
  end
end
