defmodule RompCrm.SmsBookingConsent do
  @moduledoc """
  Ensures customer booking texts are not sent until the contractor confirms,
  and builds pending booking proposals from new leads without a set date.
  """

  alias RompCrm.Twilio.Phone

  @consent_re ~r/\b(text|reach out|contact|schedule with|send (her|him|them)|booking (message|text|link)|have (her|him|them) pick a time)\b/i

  @doc """
  Returns `{job_ops, booking_ops, pending_proposals}` where `pending_proposals`
  is a list of maps to store after the job create runs.
  """
  def guard_operations(job_ops, booking_ops, body_text, proposed_booking_raw)
      when is_list(job_ops) and is_list(booking_ops) and is_binary(body_text) do
    proposed = normalize_proposed_list(proposed_booking_raw)
    consent? = contractor_consented?(body_text)
    creates = Enum.filter(job_ops, &match?({:create, _}, &1))

    {booking_ops, extra_pending} =
      if consent? or creates == [] do
        {booking_ops, []}
      else
        strip_same_turn_initiates(booking_ops, creates)
      end

    pending =
      if consent? or creates == [] do
        extra_pending
      else
        build_pending_proposals(creates, proposed, extra_pending)
      end

    {job_ops, booking_ops, pending}
  end

  defp contractor_consented?(body) do
    prefix =
      case :binary.match(body, "{") do
        {pos, _} -> String.slice(body, 0, pos)
        :nomatch -> body
      end

    t = String.trim(prefix)
    t != "" and String.match?(t, @consent_re)
  end

  defp strip_same_turn_initiates(booking_ops, creates) do
    {kept, stripped} =
      Enum.split_with(booking_ops, fn
        {:booking_initiate, attrs} ->
          not matches_any_create?(attrs, creates)

        _ ->
          true
      end)

    pending_from_stripped =
      Enum.map(stripped, fn {:booking_initiate, attrs} -> attrs end)

    {kept, pending_from_stripped}
  end

  defp matches_any_create?(attrs, creates) do
    phone_norm = Phone.normalize_us(attrs.phone || "")

    Enum.any?(creates, fn {:create, job_attrs} ->
      create_phone = Phone.normalize_us(job_attrs[:phone] || "")

      cond do
        phone_norm != "" and create_phone != "" -> phone_norm == create_phone
        true -> same_name?(job_attrs[:client_name], attrs.client_name)
      end
    end)
  end

  defp build_pending_proposals(creates, proposed, stripped_pending) do
    creates
    |> Enum.flat_map(fn {:create, attrs} ->
      if lead_has_scheduled_date?(attrs) do
        []
      else
        phone = attrs[:phone]

        if valid_phone?(phone) do
          [pick_proposal_attrs(attrs, proposed, stripped_pending)]
        else
          []
        end
      end
    end)
    |> Enum.uniq_by(fn attrs ->
      Phone.normalize_us(attrs["phone"] || Map.get(attrs, :phone) || "")
    end)
  end

  defp lead_has_scheduled_date?(%{scheduled_on: %Date{}}), do: true

  defp lead_has_scheduled_date?(%{work_items: items}) when is_list(items) do
    Enum.any?(items, fn item ->
      is_map(item) and (Map.get(item, :scheduled_on) != nil or Map.get(item, "scheduled_on") != nil)
    end)
  end

  defp lead_has_scheduled_date?(_), do: false

  defp pick_proposal_attrs(create_attrs, proposed, stripped_pending) do
    phone_norm = Phone.normalize_us(create_attrs[:phone] || "")

    from_proposed =
      Enum.find(proposed, fn p ->
        Phone.normalize_us(p["phone"] || p[:phone] || "") == phone_norm
      end)

    from_stripped =
      Enum.find(stripped_pending, fn p ->
        Phone.normalize_us(p.phone || "") == phone_norm
      end)

    base =
      cond do
        from_proposed -> from_proposed
        from_stripped -> from_stripped
        true -> %{}
      end
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    %{
      "client_name" => base["client_name"] || create_attrs[:client_name] || "",
      "phone" => create_attrs[:phone] || base["phone"] || "",
      "job_type_label" =>
        base["job_type_label"] || create_attrs[:work_description] || "service call",
      "duration_min_minutes" => parse_int(base["duration_min_minutes"], 90),
      "duration_max_minutes" => parse_int(base["duration_max_minutes"], 120)
    }
  end

  defp normalize_proposed_list(list) when is_list(list), do: list
  defp normalize_proposed_list(_), do: []

  defp valid_phone?(phone) when is_binary(phone) do
    norm = Phone.normalize_us(phone)
    norm != "" and Phone.to_e164(norm) != nil
  end

  defp valid_phone?(_), do: false

  defp same_name?(a, b) when is_binary(a) and is_binary(b) do
    norm = fn s -> s |> String.downcase() |> String.trim() end
    norm.(a) != "" and norm.(a) == norm.(b)
  end

  defp same_name?(_, _), do: false

  defp parse_int(v, default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
