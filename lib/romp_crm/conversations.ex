defmodule RompCrm.Conversations do
  @moduledoc """
  Thread-agnostic conversation listing and UI formatting.

  Today: **`:agent`** threads (SMS + in-app messages to the RompCRM AI agent).
  Future: **`:client`** threads keyed by customer/contact id for outbound client SMS.
  """

  alias RompCrm.Accounts.User
  alias RompCrm.Employees
  alias RompCrm.SmsConversations
  alias RompCrm.SmsMms

  @type thread_kind :: :agent | :client

  @doc """
  Messages for a thread, oldest first.

  **`:agent`** — all persisted agent lines for the workspace (SMS and in-app).
  """
  def list_thread_messages(:agent, business_id, opts \\ []) when is_integer(business_id) do
    SmsConversations.list_business_agent_messages(business_id, opts)
  end

  @doc "Build display rows for a chat UI (`viewer_user` is the logged-in user)."
  def format_thread_rows(messages, %User{} = viewer_user, business_id) when is_list(messages) do
    names = display_names_for_users(business_id, messages)

    Enum.map(messages, fn msg ->
      {label, role, side} = sender_meta(msg, viewer_user.id, names)
      text = display_text(msg.body)
      photos = photo_urls(msg.body)

      %{
        id: msg.id,
        label: label,
        role: role,
        side: side,
        text: text,
        photos: photos,
        inserted_at: msg.inserted_at,
        channel: msg.channel || "sms"
      }
    end)
  end

  defp display_names_for_users(business_id, messages) do
    user_ids =
      messages
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.reduce(user_ids, %{}, fn uid, acc ->
      name =
        case Employees.get_employee_by_user_id(uid, business_id) do
          %{name: n} when is_binary(n) and n != "" -> n
          _ -> nil
        end

      Map.put(acc, uid, name || "Team member")
    end)
  end

  defp sender_meta(%{direction: "outbound"}, _viewer_id, _names) do
    {"RompCRM agent", :agent, :left}
  end

  defp sender_meta(%{direction: "inbound", user_id: uid} = msg, viewer_id, _names)
       when uid == viewer_id do
    label =
      case msg.channel do
        "in_app" -> "You"
        _ -> "You (sms)"
      end

    {label, :self, :right}
  end

  defp sender_meta(%{direction: "inbound", user_id: uid}, _viewer_id, names) do
    {Map.get(names, uid, "Team member"), :employee, :right}
  end

  defp display_text(body) when is_binary(body) do
    body
    |> String.split(~r/\n\n\[MMS attachments|\n\n\[Twilio MMS|\n\n\[In-app photo/i)
    |> hd()
    |> String.trim()
    |> case do
      "" -> nil
      "(Inbound SMS body empty.)" -> nil
      t -> t
    end
  end

  defp display_text(_), do: nil

  defp photo_urls(body) when is_binary(body) do
    SmsMms.extract_twilio_media_urls(body)
  end

  defp photo_urls(_), do: []
end
