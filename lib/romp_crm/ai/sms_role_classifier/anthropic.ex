defmodule RompCrm.Ai.SmsRoleClassifier.Anthropic do
  @moduledoc false

  @api "https://api.anthropic.com/v1/messages"
  @finch RompCrm.Finch

  def classify(body, context) when is_binary(body) and is_map(context) do
    api_key = Application.get_env(:romp_crm, :anthropic_api_key)
    model = Application.get_env(:romp_crm, :anthropic_model, "claude-sonnet-4-6")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      call_claude(api_key, model, body, context)
    end
  end

  defp call_claude(api_key, model, body, context) do
    pending? = Map.get(context, :pending_prompt, false) == true
    names = Map.get(context, :business_names, []) |> List.wrap() |> Enum.join(", ")

    user = """
    A phone number may be both a Romp CRM contractor and a customer in an open booking conversation.

    Pending disambiguation prompt already sent to them: #{pending?}
    Scheduling business name(s): #{if names == "", do: "(unknown)", else: names}

    Latest SMS:
    ---
    #{body}
    ---

    Decide the role for this message. Respond with JSON only:
    {"role":"client"} — about scheduling/booking with the business that texted them
    {"role":"contractor"} — about managing their own Romp CRM jobs/clients/time
    {"role":"ask"} — unclear; server will ask which they mean
    """

    system =
      "You classify SMS role for a dual-role phone. Use semantic judgment, not keyword lists. JSON only."

    req_body = %{
      model: model,
      max_tokens: 256,
      system: system,
      messages: [%{role: "user", content: user}]
    }

    case Req.post(@api,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"},
             {"content-type", "application/json"}
           ],
           json: req_body,
           finch: @finch,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: resp}} ->
        parse_response(resp)

      {:ok, %{status: status, body: err_body}} ->
        {:error, {:anthropic_http, status, err_body}}

      {:error, reason} ->
        {:error, {:request, reason}}
    end
  end

  defp parse_response(%{"content" => [%{"text" => text} | _]}) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/^```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```$/m, "")

    case Jason.decode(cleaned) do
      {:ok, %{"role" => role}} -> {:ok, role}
      _ ->
        case Regex.run(~r/\{[\s\S]*\}/, cleaned) do
          [json] ->
            case Jason.decode(json) do
              {:ok, %{"role" => role}} -> {:ok, role}
              _ -> {:error, :invalid_json_from_model}
            end

          _ ->
            {:error, :invalid_json_from_model}
        end
    end
  end

  defp parse_response(_), do: {:error, :unexpected_response}
end
