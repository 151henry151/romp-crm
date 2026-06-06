defmodule RompCrm.Clients.MatchSuggest do
  @moduledoc """
  Suggests existing clients that may match contact details entered on a new job.
  Uses Claude when configured; falls back to deterministic matching.
  """

  alias RompCrm.Clients
  alias RompCrm.Clients.ClientContact
  alias RompCrm.Clients.MatchSuggest.Anthropic

  @type result ::
          {:ok, :no_match}
          | {:ok, {:ambiguous, [map()]}}
          | {:error, term()}

  @doc """
  Returns `{:ok, :no_match}`, `{:ok, {:ambiguous, candidates}}`, or `{:error, reason}`.

  Each candidate includes **`id`**, **`client_name`**, and a short **`reason`** string for the UI.
  """
  def suggest(business_id, contact_attrs) when is_integer(business_id) and is_map(contact_attrs) do
    contact = normalize_contact(contact_attrs)

    if ClientContact.has_identity?(contact) do
      case anthropic_suggest(business_id, contact) do
        {:ok, result} ->
          {:ok, result}

        {:error, _} ->
          {:ok, deterministic_suggest(business_id, contact)}
      end
    else
      {:ok, :no_match}
    end
  end

  defp anthropic_suggest(business_id, contact) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)

    if is_binary(api_key) and api_key != "" do
      Anthropic.suggest(business_id, contact, Clients.snapshot_for_sms_ai(business_id))
    else
      {:error, :missing_api_key}
    end
  end

  defp deterministic_suggest(business_id, contact) do
    matches =
      business_id
      |> Clients.list_clients()
      |> Enum.filter(fn client ->
        ClientContact.same_client?(ClientContact.from_struct(client), contact)
      end)
      |> Enum.map(&candidate_row/1)

    case matches do
      [] -> :no_match
      list -> {:ambiguous, list}
    end
  end

  defp normalize_contact(attrs) do
    attrs
    |> Enum.map(fn {k, v} -> {if(is_atom(k), do: k, else: String.to_atom(to_string(k))), v} end)
    |> Map.new()
  end

  defp candidate_row(%{id: id, client_name: name} = client) do
    %{
      id: id,
      client_name: name || "",
      reason: ClientContact.normalize_name(name) <> " — existing client"
    }
  end
end
