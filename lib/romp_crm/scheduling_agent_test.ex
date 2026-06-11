defmodule RompCrm.SchedulingAgentTest do
  @moduledoc """
  Isolated two-pane sandbox for previewing contractor ↔ agent and client ↔
  scheduling assistant interactions without touching real jobs, clients, or SMS.
  """

  alias RompCrm.Accounts.User
  alias RompCrm.Repo
  alias RompCrm.SchedulingAgentTest.{Client, Contractor, Record, Sandbox}

  @doc "Loads or creates the sandbox session for this user and business."
  def get_or_create_session(%User{id: user_id}, business_id) when is_integer(business_id) do
    case Repo.get_by(Record, user_id: user_id, business_id: business_id) do
      %Record{} = row ->
        Sandbox.decode(row.state_json)

      nil ->
        state = Sandbox.fresh_state()

        %Record{}
        |> Record.changeset(%{
          user_id: user_id,
          business_id: business_id,
          state_json: Sandbox.encode(state)
        })
        |> Repo.insert!()

        state
    end
  end

  @doc "Persists sandbox state."
  def save_session(%User{id: user_id}, business_id, state)
      when is_integer(business_id) and is_map(state) do
    encoded = Sandbox.encode(state)

    case Repo.get_by(Record, user_id: user_id, business_id: business_id) do
      %Record{} = row ->
        row |> Record.changeset(%{state_json: encoded}) |> Repo.update!()

      nil ->
        %Record{}
        |> Record.changeset(%{user_id: user_id, business_id: business_id, state_json: encoded})
        |> Repo.insert!()
    end

    :ok
  end

  @doc "Clears the sandbox and restores the welcome message."
  def reset_session(%User{} = user, business_id) when is_integer(business_id) do
    state = Sandbox.fresh_state()
    save_session(user, business_id, state)
    state
  end

  @doc false
  def send_contractor(%User{} = user, business_id, body) when is_integer(business_id) do
    state = get_or_create_session(user, business_id)

    case Contractor.process(state, user, business_id, body) do
      {:ok, state, meta} ->
        save_session(user, business_id, state)
        {:ok, meta}

      other ->
        other
    end
  end

  @doc false
  def send_client(%User{} = user, business_id, body) when is_integer(business_id) do
    state = get_or_create_session(user, business_id)

    case Client.process(state, user, business_id, body) do
      {:ok, state, reply} ->
        save_session(user, business_id, state)
        {:ok, reply}

      {:error, :no_active_link} = err ->
        err

      other ->
        other
    end
  end

  @doc "Formats contractor pane rows for `ChatComponents.chat_thread/1`."
  def contractor_rows(state) do
    (state["contractor_turns"] || [])
    |> Enum.with_index()
    |> Enum.map(fn {turn, idx} ->
      case turn do
        %{"role" => "contractor", "text" => text} ->
          row("contractor-#{idx}", "You", :self, :right, text)

        %{"role" => "assistant", "text" => text} ->
          row("contractor-agent-#{idx}", "RompCRM agent", :agent, :left, text)

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Formats test-client pane rows for `ChatComponents.chat_thread/1`."
  def client_rows(state) do
    name = Sandbox.client_display_name(state)

    (state["client_turns"] || [])
    |> Enum.with_index()
    |> Enum.map(fn {turn, idx} ->
      case turn do
        %{"role" => "client", "text" => text} ->
          row("client-#{idx}", "#{name} (test customer)", :self, :right, text)

        %{"role" => "scheduling_assistant", "text" => text} ->
          row("client-agent-#{idx}", "Scheduling assistant", :agent, :left, text)

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def client_pane_active?(state), do: Sandbox.active_client_link(state) != nil

  defp row(id, label, role, side, text) do
    %{id: id, label: label, role: role, side: side, text: text, photos: []}
  end
end
