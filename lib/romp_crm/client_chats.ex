defmodule RompCrm.ClientChats do
  @moduledoc """
  Client-facing scheduling SMS threads: list, human takeover, live replies, and handoff
  back to the scheduling agent.
  """

  import Ecto.Query

  alias RompCrm.Bookings.BookingLink
  alias RompCrm.ClientChats.Takeover
  alias RompCrm.Repo
  alias RompCrm.SmsConversations
  alias RompCrm.Twilio.Messages
  alias RompCrm.Twilio.Phone

  @takeover_intro_sms "We're connecting you with a team member now — please hold on a moment."

  @handoff_sms "You're back with our scheduling assistant — reply anytime to pick up where we left off."

  @pubsub RompCrm.PubSub

  @doc "Summaries for the chats sidebar, newest activity first."
  def list_thread_summaries(business_id) when is_integer(business_id) do
    phones =
      Repo.all(
        from m in RompCrm.SmsConversations.Message,
          where: m.business_id == ^business_id and m.thread_kind == "client",
          group_by: m.phone_normalized,
          select: %{
            phone_normalized: m.phone_normalized,
            last_at: max(m.inserted_at),
            last_id: max(m.id)
          },
          order_by: [desc: max(m.inserted_at)]
      )

    takeovers = takeover_map(business_id)

    Enum.map(phones, fn row ->
      last_msg = Repo.get(RompCrm.SmsConversations.Message, row.last_id)
      link = primary_link_for_phone(business_id, row.phone_normalized)

      %{
        id: "client:#{row.phone_normalized}",
        kind: :client,
        phone_normalized: row.phone_normalized,
        client_name: client_name_for_link(link),
        job_type_label: link && link.job_type_label,
        last_preview: preview_body(last_msg && last_msg.body),
        last_at: row.last_at,
        taken_over?: Map.has_key?(takeovers, row.phone_normalized),
        taken_over_by_user_id: get_in(takeovers, [row.phone_normalized, :taken_over_by_user_id]),
        booking_link_id: link && link.id
      }
    end)
  end

  @doc false
  def taken_over?(business_id, phone_normalized)
      when is_integer(business_id) and is_binary(phone_normalized) do
    Repo.exists?(
      from t in Takeover,
        where: t.business_id == ^business_id and t.phone_normalized == ^phone_normalized
    )
  end

  @doc false
  def get_takeover(business_id, phone_normalized) do
    Repo.get_by(Takeover, business_id: business_id, phone_normalized: phone_normalized)
  end

  @doc """
  Human takes over a client SMS thread: notify the customer, pause the scheduling agent.
  """
  def take_over!(user, business_id, phone_normalized) when is_integer(business_id) do
    link = primary_link_for_phone(business_id, phone_normalized)
    tech_id = (link && link.technician_user_id) || user.id

    with {:ok, e164} <- client_e164(phone_normalized),
         :ok <- send_and_record(tech_id, business_id, phone_normalized, e164, @takeover_intro_sms, "sms_human") do
      attrs = %{
        business_id: business_id,
        phone_normalized: phone_normalized,
        taken_over_by_user_id: user.id,
        booking_link_id: link && link.id
      }

      case Repo.get_by(Takeover, business_id: business_id, phone_normalized: phone_normalized) do
        nil ->
          %Takeover{} |> Takeover.changeset(attrs) |> Repo.insert!()

        row ->
          row |> Takeover.changeset(attrs) |> Repo.update!()
      end

      broadcast(business_id, phone_normalized, :takeover)
      :ok
    end
  end

  @doc """
  Return the thread to the scheduling agent and notify the customer.
  """
  def hand_off!(user, business_id, phone_normalized) when is_integer(business_id) do
    link = primary_link_for_phone(business_id, phone_normalized)
    tech_id = (link && link.technician_user_id) || user.id

    with {:ok, e164} <- client_e164(phone_normalized),
         :ok <- send_and_record(tech_id, business_id, phone_normalized, e164, @handoff_sms, "sms_human") do
      Repo.delete_all(
        from t in Takeover,
          where: t.business_id == ^business_id and t.phone_normalized == ^phone_normalized
      )

      broadcast(business_id, phone_normalized, :handoff)
      :ok
    end
  end

  @doc "Send a live human SMS in an taken-over client thread."
  def send_human_message!(user, business_id, phone_normalized, body)
      when is_integer(business_id) and is_binary(body) do
    body = String.trim(body)

    if body == "" do
      {:error, :empty}
    else
      unless taken_over?(business_id, phone_normalized) do
        {:error, :not_taken_over}
      else
        link = primary_link_for_phone(business_id, phone_normalized)
        tech_id = (link && link.technician_user_id) || user.id

        with {:ok, e164} <- client_e164(phone_normalized),
             :ok <- send_and_record(tech_id, business_id, phone_normalized, e164, body, "sms_human") do
          broadcast(business_id, phone_normalized, :message)
          {:ok, body}
        end
      end
    end
  end

  @doc """
  When the scheduling agent path receives inbound SMS but a human has taken over,
  record the customer message only (no AI reply).
  """
  def record_inbound_while_taken_over(links, phone_norm, inbound_body) when is_list(links) do
    links
    |> Enum.filter(fn %BookingLink{} = link ->
      taken_over?(link.business_id, phone_norm)
    end)
    |> Enum.uniq_by(& &1.business_id)
    |> Enum.each(fn link ->
      _ =
        SmsConversations.record_client_message(
          link.business_id,
          link.technician_user_id,
          phone_norm,
          "inbound",
          inbound_body,
          channel: "sms"
        )
    end)

    :ok
  end

  @doc false
  def pubsub_topic(business_id, phone_normalized) do
    "client_chat:#{business_id}:#{phone_normalized}"
  end

  defp send_and_record(tech_user_id, business_id, phone_norm, e164, body, channel) do
    case Messages.send_sms(e164, body) do
      {:ok, _} ->
        _ =
          SmsConversations.record_client_message(
            business_id,
            tech_user_id,
            phone_norm,
            "outbound",
            body,
            channel: channel
          )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp client_e164(phone_normalized) do
    case Phone.to_e164(phone_normalized) do
      e164 when is_binary(e164) -> {:ok, e164}
      _ -> {:error, :invalid_phone}
    end
  end

  defp primary_link_for_phone(business_id, phone_normalized) do
    now = DateTime.utc_now(:second)

    Repo.one(
      from l in BookingLink,
        where: l.business_id == ^business_id,
        where: l.client_phone_normalized == ^phone_normalized,
        where: l.status in ["pending", "booked"],
        where: is_nil(l.expires_at) or l.expires_at > ^now,
        order_by: [desc: l.id],
        limit: 1,
        preload: [:client]
    ) ||
      Repo.one(
        from l in BookingLink,
          where: l.business_id == ^business_id,
          where: l.client_phone_normalized == ^phone_normalized,
          order_by: [desc: l.id],
          limit: 1,
          preload: [:client]
      )
  end

  defp client_name_for_link(nil), do: "Customer"
  defp client_name_for_link(%BookingLink{client: %{client_name: name}}) when is_binary(name) and name != "", do: name
  defp client_name_for_link(_), do: "Customer"

  defp preview_body(nil), do: ""
  defp preview_body(body), do: body |> to_string() |> String.slice(0, 80)

  defp takeover_map(business_id) do
    Repo.all(from t in Takeover, where: t.business_id == ^business_id)
    |> Map.new(fn t -> {t.phone_normalized, t} end)
  end

  defp broadcast(business_id, phone_normalized, event) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      pubsub_topic(business_id, phone_normalized),
      {event, business_id, phone_normalized}
    )
  end
end
