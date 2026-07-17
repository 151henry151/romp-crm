defmodule RompCrm.SmsBookingConsent do
  @moduledoc """
  Builds pending booking proposals from AI `proposed_booking_initiates` and
  unscheduling creates. Does **not** keyword-scan the contractor SMS — the
  unified extractor decides whether to emit `booking_initiate` vs propose.
  """

  alias RompCrm.Twilio.Phone

  @doc """
  Returns `{job_ops, booking_ops, pending_proposals}`.

  - `booking_initiate` ops from the AI are kept as-is (explicit outreach intent).
  - Pending proposals come from `proposed_booking_raw` and from creates that have
    a phone but no visit date (when the AI did not already initiate).
  """
  def guard_operations(job_ops, booking_ops, _body_text, proposed_booking_raw)
      when is_list(job_ops) and is_list(booking_ops) do
    proposed = normalize_proposed_list(proposed_booking_raw)
    creates = Enum.filter(job_ops, &match?({:create, _}, &1))

    pending =
      build_pending_proposals(creates, proposed, booking_ops)

    {job_ops, booking_ops, pending}
  end

  defp build_pending_proposals(creates, proposed, booking_ops) do
    initiate_phones =
      booking_ops
      |> Enum.filter(&match?({:booking_initiate, _}, &1))
      |> Enum.map(fn {:booking_initiate, attrs} -> Phone.normalize_us(attrs.phone || "") end)
      |> MapSet.new()

    from_proposed =
      Enum.map(proposed, fn p ->
        Map.new(p, fn {k, v} -> {to_string(k), v} end)
      end)

    from_creates =
      creates
      |> Enum.flat_map(fn {:create, attrs} ->
        phone = attrs[:phone]
        phone_norm = Phone.normalize_us(phone || "")

        cond do
          lead_has_scheduled_date?(attrs) ->
            []

          phone_norm != "" and MapSet.member?(initiate_phones, phone_norm) ->
            []

          valid_phone?(phone) ->
            [pick_proposal_attrs(attrs, from_proposed)]

          true ->
            []
        end
      end)

    (from_proposed ++ from_creates)
    |> Enum.reject(fn attrs ->
      phone_norm = Phone.normalize_us(attrs["phone"] || "")
      phone_norm != "" and MapSet.member?(initiate_phones, phone_norm)
    end)
    |> Enum.uniq_by(fn attrs ->
      Phone.normalize_us(attrs["phone"] || "")
    end)
  end

  defp lead_has_scheduled_date?(%{scheduled_on: %Date{}}), do: true

  defp lead_has_scheduled_date?(%{work_items: items}) when is_list(items) do
    Enum.any?(items, fn item ->
      is_map(item) and (Map.get(item, :scheduled_on) != nil or Map.get(item, "scheduled_on") != nil)
    end)
  end

  defp lead_has_scheduled_date?(_), do: false

  defp pick_proposal_attrs(create_attrs, proposed) do
    phone_norm = Phone.normalize_us(create_attrs[:phone] || "")

    from_proposed =
      Enum.find(proposed, fn p ->
        Phone.normalize_us(p["phone"] || "") == phone_norm
      end)

    base =
      (from_proposed || %{})
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

  defp parse_int(v, _default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
