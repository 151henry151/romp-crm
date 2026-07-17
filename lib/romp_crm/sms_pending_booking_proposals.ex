defmodule RompCrm.SmsPendingBookingProposals do
  @moduledoc """
  Holds a proposed customer booking SMS until the contractor confirms (e.g. reply YES).
  """

  alias RompCrm.Bookings.Orchestrator
  alias RompCrm.Repo
  alias RompCrm.SmsPendingBookingProposals.Pending
  alias RompCrm.Twilio.Phone

  # Start-anchored (like pending job confirms). Do not match affirmation words buried
  # in longer contractor messages ("we're going to do it tomorrow", "Ok don't text…").
  @confirm_re ~r/^(yes|y|confirm|confirmed|ok|okay|go ahead|do it|text (her|him|them)|send (it|the text|them)|send the scheduling)\b/i

  @doc "True when the inbound SMS confirms sending a pending customer booking text."
  def confirmation_message?(body) when is_binary(body) do
    t = String.trim(body)
    # Cap length so "Ok don't text the client, just mark the job…" is not a confirm.
    t != "" and String.match?(t, @confirm_re) and String.length(t) <= 48
  end

  def confirmation_message?(_), do: false

  @doc """
  Replace any pending row for this contractor phone. `attrs` must include
  `:client_name`, `:phone`, `:job_type_label`, duration fields, and `:job_id`.
  """
  def store!(business_id, user_id, phone_normalized, attrs)
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) and
             is_map(attrs) do
    encoded = Jason.encode!(Map.new(attrs, fn {k, v} -> {to_string(k), encode_val(v)} end))

    row_attrs = %{
      business_id: business_id,
      user_id: user_id,
      phone_normalized: phone_normalized,
      proposal_json: encoded
    }

    case Repo.get_by(Pending, business_id: business_id, phone_normalized: phone_normalized) do
      nil -> %Pending{} |> Pending.changeset(row_attrs) |> Repo.insert!()
      row -> row |> Pending.changeset(row_attrs) |> Repo.update!()
    end
  end

  @doc "Starts the booking conversation and clears the pending row."
  def apply_pending(business_id, user_id, phone_normalized, message_sid)
      when is_integer(business_id) and is_integer(user_id) and is_binary(phone_normalized) do
    case Repo.get_by(Pending, business_id: business_id, phone_normalized: phone_normalized) do
      nil ->
        :none

      %Pending{proposal_json: json, user_id: ^user_id} = row ->
        attrs = decode_proposal(json)
        op = {:booking_initiate, to_initiate_attrs(attrs)}

        {:ok, results} =
          Orchestrator.run_operations([op], %{
            business_id: business_id,
            user_id: user_id,
            message_sid: message_sid,
            created_jobs: []
          })

        Repo.delete!(row)
        {:ok, results}

      %Pending{} ->
        {:error, :wrong_user}
    end
  end

  def get(business_id, phone_normalized) when is_integer(business_id) and is_binary(phone_normalized) do
    Repo.get_by(Pending, business_id: business_id, phone_normalized: phone_normalized)
  end

  defp decode_proposal(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp to_initiate_attrs(map) do
    %{
      client_id: parse_optional_int(map["client_id"]),
      client_name: map["client_name"] || "",
      phone: map["phone"] || "",
      job_id: parse_optional_int(map["job_id"]),
      job_type_label: map["job_type_label"] || "",
      duration_min_minutes: parse_int(map["duration_min_minutes"], 90),
      duration_max_minutes: parse_int(map["duration_max_minutes"], 120)
    }
  end

  defp parse_optional_int(nil), do: nil
  defp parse_optional_int(v) when is_integer(v), do: v

  defp parse_optional_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(v, default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  defp encode_val(nil), do: nil
  defp encode_val(v), do: v
end
