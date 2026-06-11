defmodule RompCrm.SmsConversations do
  @moduledoc """
  Persists inbound/outbound SMS lines per **`business_id`** + **`phone_normalized`** so the AI can see
  recent thread context on each webhook request.

  Messages are stored in chronological order in the DB; **`list_prior_turns_for_ai/3`** returns older-first
  tuples for prompts and trims by count and total character budget.
  """

  require Logger

  import Ecto.Query

  alias RompCrm.Repo
  alias RompCrm.SmsConversations.Message

  @default_max_messages 50
  @default_max_chars 12_000

  @doc """
  Recent rows for **`business_id`** + **`phone_normalized`**, oldest first, each
  **`{:contractor | :assistant, body}`**.

  Options:

    * **`:max_messages`** — cap rows fetched (default #{@default_max_messages})
    * **`:max_chars`** — drop oldest turns until formatted thread fits (default #{@default_max_chars})

  """
  def list_prior_turns_for_ai(business_id, phone_normalized, opts \\ [])
      when is_integer(business_id) and is_binary(phone_normalized) do
    max_msgs = Keyword.get(opts, :max_messages, @default_max_messages)
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)

    rows =
      Repo.all(
        from m in Message,
          where: m.business_id == ^business_id and m.phone_normalized == ^phone_normalized,
          where: m.thread_kind == "contractor",
          order_by: [desc: m.id],
          limit: ^max_msgs,
          select: %{direction: m.direction, body: m.body}
      )

    turns =
      rows
      |> Enum.reverse()
      |> Enum.map(fn %{direction: d, body: b} ->
        role = if d == "outbound", do: :assistant, else: :contractor
        {role, b || ""}
      end)

    trim_thread_to_char_budget(turns, max_chars)
  end

  @doc """
  Client booking-thread turns for **`business_id`** + client phone, oldest first,
  each **`{:client | :assistant, body}`**. Same trimming options as
  **`list_prior_turns_for_ai/3`**.
  """
  def list_client_turns_for_ai(business_id, phone_normalized, opts \\ [])
      when is_integer(business_id) and is_binary(phone_normalized) do
    max_msgs = Keyword.get(opts, :max_messages, @default_max_messages)
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)

    rows =
      Repo.all(
        from m in Message,
          where: m.business_id == ^business_id and m.phone_normalized == ^phone_normalized,
          where: m.thread_kind == "client",
          order_by: [desc: m.id],
          limit: ^max_msgs,
          select: %{direction: m.direction, body: m.body}
      )

    turns =
      rows
      |> Enum.reverse()
      |> Enum.map(fn %{direction: d, body: b} ->
        role = if d == "outbound", do: :assistant, else: :client
        {role, b || ""}
      end)

    trim_thread_to_char_budget(turns, max_chars)
  end

  @doc """
  Appends one message to a client booking thread. **`user_id`** is the technician
  who owns the booking conversation (attribution), not the sender.
  """
  def record_client_message(business_id, user_id, phone_normalized, direction, body)
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) and
             direction in ["inbound", "outbound"] and is_binary(body) do
    %Message{}
    |> Message.changeset(%{
      business_id: business_id,
      user_id: user_id,
      phone_normalized: phone_normalized,
      direction: direction,
      body: String.slice(String.trim(body), 0, 6000),
      channel: "sms",
      thread_kind: "client"
    })
    |> Repo.insert()
  end

  defp trim_thread_to_char_budget(turns, max_chars) do
    orig_len = length(turns)
    trimmed = trim_thread_loop(turns, max_chars)

    dropped = orig_len - length(trimmed)

    if dropped > 0 do
      Logger.info(
        "SmsConversations: trimmed #{dropped} oldest turns from AI context (max_chars=#{max_chars})"
      )
    end

    trimmed
  end

  defp trim_thread_loop(turns, max_chars) do
    cond do
      turns == [] ->
        []

      String.length(format_turn_lines(turns)) <= max_chars ->
        turns

      true ->
        case turns do
          [_ | rest] -> trim_thread_loop(rest, max_chars)
          [] -> []
        end
    end
  end

  defp format_turn_lines(turns) do
    turns
    |> Enum.map(fn {role, text} ->
      label = if role == :assistant, do: "Assistant", else: "Contractor"
      "#{label}: #{text}"
    end)
    |> Enum.join("\n")
  end

  @doc """
  All agent-thread messages for a workspace (every team member's SMS and in-app lines), oldest first.
  """
  def list_business_agent_messages(business_id, opts \\ []) when is_integer(business_id) do
    limit = Keyword.get(opts, :limit, 500)

    Repo.all(
      from m in Message,
        where: m.business_id == ^business_id,
        where: m.thread_kind == "contractor",
        order_by: [asc: m.id],
        limit: ^limit,
        preload: [:user]
    )
  end

  @doc "Recent inbound message bodies (newest first), for MMS job/photo inference."
  def recent_inbound_bodies(business_id, phone_normalized, opts \\ [])
      when is_integer(business_id) and is_binary(phone_normalized) do
    limit = Keyword.get(opts, :limit, 5)

    Repo.all(
      from m in Message,
        where: m.business_id == ^business_id,
        where: m.phone_normalized == ^phone_normalized,
        where: m.direction == "inbound",
        where: m.thread_kind == "contractor",
        order_by: [desc: m.id],
        limit: ^limit,
        select: m.body
    )
  end

  @doc """
  Append the current inbound SMS and the assistant reply we sent (two rows, one transaction).

  Bodies are truncated for safety before insert. Returns **`{:ok, :ok}`** or **`{:error, reason}`**.
  """
  def record_exchange(business_id, user_id, phone_normalized, inbound_body, outbound_body, opts \\ [])
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) and
             is_binary(inbound_body) and is_binary(outbound_body) do
    channel = Keyword.get(opts, :channel, "sms")
    inbound_body = String.slice(String.trim(inbound_body), 0, 6000)
    outbound_body = String.slice(String.trim(outbound_body), 0, 6000)

    Repo.transaction(fn ->
      with {:ok, _} <-
             insert_message(business_id, user_id, phone_normalized, "inbound", inbound_body, channel),
           {:ok, _} <-
             insert_message(business_id, user_id, phone_normalized, "outbound", outbound_body, channel) do
        :ok
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp insert_message(business_id, user_id, phone_normalized, direction, body, channel) do
    %Message{}
    |> Message.changeset(%{
      business_id: business_id,
      user_id: user_id,
      phone_normalized: phone_normalized,
      direction: direction,
      body: body,
      channel: channel
    })
    |> Repo.insert()
  end
end
