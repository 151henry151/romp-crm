defmodule RompCrm.Ai.SmsRoleClassifier do
  @moduledoc """
  Classifies whether a dual-role phone's inbound SMS is **client scheduling**,
  **contractor CRM**, or needs a clarifying ask.

  Configure **`sms_role_classifier_adapter`** (tests use **`DeterministicStub`**).
  """

  @type role :: :client | :contractor | :ask

  @doc """
  Returns `{:ok, :client | :contractor | :ask}` or `{:error, reason}`.

  `context` keys:
  - `:pending_prompt` — bool (already asked which role)
  - `:business_names` — list of business name strings for scheduling side
  - `:dual_role` — bool (registered contractor + active booking links)
  """
  def classify(body, context \\ %{}) when is_binary(body) and is_map(context) do
    mod =
      Application.get_env(
        :romp_crm,
        :sms_role_classifier_adapter,
        __MODULE__.Anthropic
      )

    case mod.classify(body, context) do
      {:ok, role} when role in [:client, :contractor, :ask] -> {:ok, role}
      {:ok, "client"} -> {:ok, :client}
      {:ok, "contractor"} -> {:ok, :contractor}
      {:ok, "ask"} -> {:ok, :ask}
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end
end
