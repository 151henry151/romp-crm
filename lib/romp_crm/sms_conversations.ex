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
  Append the current inbound SMS and the assistant reply we sent (two rows, one transaction).

  Bodies are truncated for safety before insert. Returns **`{:ok, :ok}`** or **`{:error, reason}`**.
  """
  def record_exchange(business_id, user_id, phone_normalized, inbound_body, outbound_body)
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) and
             is_binary(inbound_body) and is_binary(outbound_body) do
    inbound_body = String.slice(String.trim(inbound_body), 0, 6000)
    outbound_body = String.slice(String.trim(outbound_body), 0, 6000)

    Repo.transaction(fn ->
      %Message{}
      |> Message.changeset(%{
        business_id: business_id,
        user_id: user_id,
        phone_normalized: phone_normalized,
        direction: "inbound",
        body: inbound_body
      })
      |> Repo.insert!()

      %Message{}
      |> Message.changeset(%{
        business_id: business_id,
        user_id: user_id,
        phone_normalized: phone_normalized,
        direction: "outbound",
        body: outbound_body
      })
      |> Repo.insert!()

      :ok
    end)
  end
end
