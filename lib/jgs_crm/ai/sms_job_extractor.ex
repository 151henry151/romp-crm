defmodule JgsCrm.Ai.SmsJobExtractor do
  @moduledoc """
  Turns free-form SMS text into attributes for `JgsCrm.Jobs.Job` via a configured
  adapter (Anthropic Claude in production, deterministic stub in tests).
  """

  alias JgsCrm.Jobs.Job

  @doc """
  Returns `{:ok, attrs}` with atom keys suitable for `JgsCrm.Jobs.create_job/1`,
  or `{:error, reason}`.
  """
  def extract(raw_message) when is_binary(raw_message) do
    mod = Application.get_env(:jgs_crm, :sms_job_extractor_adapter, __MODULE__.Anthropic)

    case mod.extract(raw_message) do
      {:ok, attrs} when is_map(attrs) -> {:ok, normalize(attrs)}
      {:error, _} = err -> err
      other -> {:error, {:unexpected, other}}
    end
  end

  defp normalize(attrs) when is_map(attrs) do
    m =
      attrs
      |> stringify_map()
      |> trim_fields()

    client_name =
      if blank?(m["client_name"]) do
        "Lead from SMS"
      else
        String.trim(m["client_name"])
      end

    %{
      client_name: client_name,
      address: nilify_blank(m["address"]),
      phone: nilify_blank(m["phone"]),
      work_description: nilify_blank(m["work_description"]),
      priority: coerce_enum(m["priority"], Job.priorities(), :normal),
      status: coerce_enum(m["status"], Job.statuses(), :lead),
      referred_by: nilify_blank(m["referred_by"]),
      notes: nilify_blank(m["notes"]),
      next_action: nilify_blank(m["next_action"])
    }
  end

  defp stringify_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp trim_fields(map) do
    Map.new(map, fn {k, v} -> {k, trim_val(v)} end)
  end

  defp trim_val(v) when is_binary(v), do: String.trim(v)
  defp trim_val(v), do: v

  defp blank?(v) when v in [nil, ""], do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  defp nilify_blank(v) do
    cond do
      blank?(v) -> nil
      is_binary(v) -> String.trim(v)
      true -> v |> to_string() |> String.trim()
    end
  end

  defp coerce_enum(raw, allowed, default) do
    normalized = normalize_enum_string(raw)

    Enum.find(allowed, fn atom -> Atom.to_string(atom) == normalized end) || default
  end

  defp normalize_enum_string(raw) when is_atom(raw), do: Atom.to_string(raw)

  defp normalize_enum_string(raw) when is_binary(raw) do
    s = raw |> String.trim() |> String.downcase()

    case s do
      "in progress" -> "in_progress"
      other -> other
    end
  end

  defp normalize_enum_string(_), do: ""
end
