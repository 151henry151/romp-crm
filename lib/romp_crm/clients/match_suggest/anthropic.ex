defmodule RompCrm.Clients.MatchSuggest.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def suggest(business_id, contact, clients_snapshot)
      when is_integer(business_id) and is_map(contact) and is_list(clients_snapshot) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-20250514")

    body = %{
      model: model,
      max_tokens: 1024,
      system: system_prompt(),
      messages: [
        %{
          role: "user",
          content: user_text(business_id, contact, clients_snapshot)
        }
      ]
    }

    case Req.post(@api,
           finch: @finch,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           json: body,
           receive_timeout: 45_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        parse_response(text, clients_snapshot)

      {:ok, %{status: status, body: body}} ->
        {:error, {:anthropic, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp system_prompt do
    """
    You match new job contact details to existing CRM clients. Reply with JSON only — no markdown.

    Schema:
    {"match":"none"}
    OR
    {"match":"ambiguous","candidates":[{"id":123,"reason":"short phrase"}]}

    Rules:
    - Include a candidate only when the new details likely refer to that existing person/place (typos OK).
    - Use only client ids from the provided clients list.
    - If zero plausible matches, return match none.
    - If one or more plausible matches, return ambiguous with each id once and a brief reason.
    - Do not invent ids.
    """
  end

  defp user_text(_business_id, contact, clients_snapshot) do
    """
    New job contact details:
    #{Jason.encode!(contact)}

    Existing clients (JSON):
    #{Jason.encode!(clients_snapshot)}
    """
  end

  defp parse_response(text, clients_snapshot) do
    allowed = MapSet.new(Enum.map(clients_snapshot, & &1.id))

    with {:ok, map} <- Jason.decode(String.trim(text)),
         true <- is_map(map) do
      case map["match"] do
        "none" ->
          {:ok, :no_match}

        "ambiguous" ->
          cands =
            (map["candidates"] || [])
            |> Enum.filter(fn c ->
              is_map(c) and is_integer(c["id"]) and MapSet.member?(allowed, c["id"])
            end)
            |> Enum.map(fn c ->
              name =
                clients_snapshot
                |> Enum.find_value("", fn row ->
                  if row.id == c["id"], do: row.client_name || "", else: nil
                end)

              %{
                id: c["id"],
                client_name: name,
                reason: to_string(c["reason"] || "Possible match")
              }
            end)
            |> Enum.uniq_by(& &1.id)

          if cands == [] do
            {:ok, :no_match}
          else
            {:ok, {:ambiguous, cands}}
          end

        _ ->
          {:ok, :no_match}
      end
    else
      _ -> {:ok, :no_match}
    end
  end
end
