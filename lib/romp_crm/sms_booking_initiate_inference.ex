defmodule RompCrm.SmsBookingInitiateInference do
  @moduledoc """
  When the unified contractor SMS extractor creates a lead with a customer phone
  but omits `booking_actions`, infer a booking initiate from the create op.
  """

  alias RompCrm.Twilio.Phone

  @default_min_minutes 90
  @default_max_minutes 120

  @lead_only_re ~r/\b(just\s+(add|save|create)\s+(a\s+)?lead|don'?t\s+(text|contact|reach)|do\s+not\s+(text|contact)|no\s+text|lead\s+only|save\s+for\s+later)\b/i

  @doc """
  Returns booking ops to append (empty or one `{:booking_initiate, attrs}` tuple).
  """
  def supplement(booking_ops, job_ops, raw_body)
      when is_list(booking_ops) and is_list(job_ops) and is_binary(raw_body) do
    if booking_ops != [] or lead_only_intent?(raw_body) do
      []
    else
      case infer_from_creates(job_ops) do
        nil -> []
        op -> [op]
      end
    end
  end

  defp lead_only_intent?(body) do
    t = String.trim(body)
    t != "" and String.match?(t, @lead_only_re)
  end

  defp infer_from_creates(job_ops) do
    Enum.find_value(job_ops, fn
      {:create, attrs} when is_map(attrs) ->
        phone = Map.get(attrs, :phone)
        work = Map.get(attrs, :work_description)
        name = Map.get(attrs, :client_name) || ""

        if valid_phone?(phone) and present?(work) do
          label = job_type_label(work, name)

          {:booking_initiate,
           %{
             client_id: Map.get(attrs, :client_id),
             client_name: name,
             phone: phone,
             job_id: nil,
             job_type_label: label,
             duration_min_minutes: @default_min_minutes,
             duration_max_minutes: @default_max_minutes
           }}
        end

      _ ->
        nil
    end)
  end

  defp valid_phone?(phone) when is_binary(phone) do
    norm = Phone.normalize_us(phone)
    norm != "" and Phone.to_e164(norm) != nil
  end

  defp valid_phone?(_), do: false

  defp present?(s) when is_binary(s), do: String.trim(s) != ""
  defp present?(_), do: false

  defp job_type_label(work, name) do
    work = String.trim(work)

    cond do
      work != "" -> work
      name != "" -> "work for #{name}"
      true -> "service call"
    end
  end
end
