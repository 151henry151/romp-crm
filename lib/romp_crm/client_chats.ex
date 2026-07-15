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
        taken_over_by_user_id: takeover_user_id(takeovers, row.phone_normalized),
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
  def taken_over_anywhere?(phone_normalized) when is_binary(phone_normalized) do
    Repo.exists?(from t in Takeover, where: t.phone_normalized == ^phone_normalized)
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

  @doc "Send a live human SMS/MMS in a taken-over client thread."
  def send_human_message!(user, business_id, phone_normalized, body, opts \\ [])
      when is_integer(business_id) and is_binary(body) and is_list(opts) do
    body = String.trim(body)

    media_urls =
      opts
      |> Keyword.get(:media_urls, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(RompCrm.ChatMedia.max_images())

    cond do
      body == "" and media_urls == [] ->
        {:error, :empty}

      not taken_over?(business_id, phone_normalized) ->
        {:error, :not_taken_over}

      true ->
        link = primary_link_for_phone(business_id, phone_normalized)
        tech_id = (link && link.technician_user_id) || user.id
        stored_body = body_with_media_suffix(body, media_urls)

        with {:ok, e164} <- client_e164(phone_normalized),
             :ok <-
               send_and_record(
                 tech_id,
                 business_id,
                 phone_normalized,
                 e164,
                 stored_body,
                 "sms_human",
                 media_urls
               ) do
          broadcast(business_id, phone_normalized, :message)
          {:ok, stored_body}
        end
    end
  end

  defp body_with_media_suffix(body, []), do: body

  defp body_with_media_suffix(body, media_urls) do
    base =
      if body == "" do
        "(Outbound MMS.)"
      else
        body
      end

    lines =
      media_urls
      |> Enum.with_index(1)
      |> Enum.map_join("", fn {u, ix} -> "\n#{ix}. #{u}" end)

    base <> "\n\n[MMS attachments — #{length(media_urls)} URL(s) stored for follow-up:]" <> lines
  end

  @doc """
  When the scheduling agent path receives inbound SMS but a human has taken over,
  record the customer message only (no AI reply).

  Uses active takeover rows — not pending booking links — so inbound still works
  after a visit is already booked.
  """
  def record_inbound_while_taken_over(phone_norm, inbound_body) when is_binary(phone_norm) do
    Repo.all(from t in Takeover, where: t.phone_normalized == ^phone_norm)
    |> Enum.each(fn takeover ->
      link =
        case takeover.booking_link_id do
          id when is_integer(id) -> Repo.get(BookingLink, id)
          _ -> primary_link_for_phone(takeover.business_id, phone_norm)
        end

      tech_id =
        (link && link.technician_user_id) || takeover.taken_over_by_user_id

      _ =
        SmsConversations.record_client_message(
          takeover.business_id,
          tech_id,
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

  defp send_and_record(tech_user_id, business_id, phone_norm, e164, body, channel, media_urls \\ []) do
    twilio_result =
      if media_urls == [] do
        Messages.send_sms(e164, body_for_twilio(body))
      else
        Messages.send_mms(e164, body_for_twilio(body), media_urls)
      end

    case twilio_result do
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

  # Twilio gets caption only — not the stored MMS URL suffix used for the web UI.
  defp body_for_twilio(body) when is_binary(body) do
    body
    |> String.split(~r/\n\n\[MMS attachments/i)
    |> hd()
    |> String.trim()
    |> case do
      "(Outbound MMS.)" -> ""
      other -> other
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

  defp takeover_user_id(takeovers, phone_normalized) do
    case Map.get(takeovers, phone_normalized) do
      %Takeover{taken_over_by_user_id: user_id} -> user_id
      _ -> nil
    end
  end

  defp broadcast(business_id, phone_normalized, event) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      pubsub_topic(business_id, phone_normalized),
      {event, business_id, phone_normalized}
    )
  end
end
