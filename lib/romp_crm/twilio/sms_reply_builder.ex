defmodule RompCrm.Twilio.SmsReplyBuilder do
  @moduledoc """
  Builds short SMS confirmations from CRM operation outcomes.

  Keeps copy under ~300 characters when possible.
  """

  alias RompCrm.Addresses
  alias RompCrm.Jobs.Job
  alias RompCrm.Reminders.Reminder

  @max_len 320

  @service_address_fields ~w(address address_line1 address_line2 city state postal_code)
  @billing_address_fields ~w(
    billing_address_different
    billing_address_line1
    billing_address_line2
    billing_city
    billing_state
    billing_postal_code
  )

  @doc """
  `results` is a list of `{:created, %Job{}}`, `{:updated, %Job{}, [field]}`,
  `{:skipped, atom}`, `{:error, atom}` in order.
  """
  def compose(assistant_sms \\ nil, results) when is_list(results) do
    summary = summarize_results(results)
    assistant = assistant_sms |> to_string() |> String.trim()
    address_confirmation = build_address_confirmations(results)

    failure_ct =
      Enum.count(results, fn r ->
        match?({:skipped, _}, r) or match?({:error, _}, r)
      end)

    assistant = apply_address_confirmations(assistant, address_confirmation)

    base =
      cond do
        failure_ct > 0 and summary != "" ->
          summary

        photos_saved?(results) and clarifying_assistant_sms?(assistant) and summary != "" ->
          summary

        assistant != "" ->
          assistant

        address_confirmation != "" ->
          address_confirmation

        summary != "" ->
          summary

        true ->
          if failure_ct > 0, do: "Some updates couldn't be applied—open Romp CRM.", else: "Done."
      end

    base |> merge_with_failures(failure_ct) |> truncate()
  end

  defp photos_saved?(results) do
    Enum.any?(results, fn
      {:photos_saved, %Job{}, saved, _attempted} when is_integer(saved) and saved > 0 -> true
      _ -> false
    end)
  end

  defp clarifying_assistant_sms?(text) when is_binary(text) do
    t = String.downcase(text)

    String.contains?(text, "?") or
      (String.contains?(t, "which job") and String.contains?(t, "photo")) or
      (String.contains?(t, "which client") and String.contains?(t, "photo")) or
      String.contains?(t, "or one of the other")
  end

  defp clarifying_assistant_sms?(_), do: false

  defp merge_with_failures(text, 0), do: text

  defp merge_with_failures(text, n) when n > 0 do
    if String.contains?(text, "skipped") or String.contains?(text, "couldn't"),
      do: text,
      else: text <> " (#{n} skipped.)"
  end

  defp summarize_results(results) do
    parts =
      Enum.flat_map(results, fn
        {:created, %Job{} = j} ->
          ["added #{short_client(j)}"]

        {:updated, %Job{} = j, fields, _extra} when is_list(fields) ->
          fs = fields |> Enum.map(&to_string/1) |> Enum.join(", ")
          ["updated #{short_client(j)} (#{fs})"]

        {:updated, %Job{} = j, fields} when is_list(fields) ->
          fs = fields |> Enum.map(&to_string/1) |> Enum.join(", ")
          ["updated #{short_client(j)} (#{fs})"]

        {:photos_saved, %Job{} = j, saved, attempted} ->
          ["saved #{saved}/#{attempted} photo(s) for #{short_client(j)}"]

        {:reminder_created, %Reminder{} = r} ->
          t = DateTime.to_iso8601(r.fire_at)
          ["saved a reminder for #{t}"]

        {:skipped, _} ->
          []

        {:error, _} ->
          []

        _ ->
          []
      end)

    case parts do
      [] -> ""
      ps -> "Got it—" <> Enum.join(ps, "; ") <> "."
    end
  end

  defp short_client(%Job{client_name: name}) do
    n = name || "lead"
    if String.length(n) > 40, do: String.slice(n, 0, 37) <> "…", else: n
  end

  defp truncate(s) do
    if String.length(s) <= @max_len, do: s, else: String.slice(s, 0, @max_len - 1) <> "…"
  end

  defp build_address_confirmations(results) do
    results
    |> Enum.flat_map(&address_confirmation_lines/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> ""
      lines -> Enum.join(lines, " ")
    end
  end

  defp address_confirmation_lines({:updated, %Job{} = job, fields, _extra}) do
    address_confirmation_lines(job, fields)
  end

  defp address_confirmation_lines({:updated, %Job{} = job, fields}) do
    address_confirmation_lines(job, fields)
  end

  defp address_confirmation_lines(_), do: []

  defp address_confirmation_lines(%Job{} = job, fields) do
    fields = normalize_field_names(fields)

    service_line =
      if service_address_updated?(fields) do
        service_address = Addresses.format_service(job)

        if blank_address?(service_address) do
          nil
        else
          "Updated #{short_client(job)}'s address to #{service_address}."
        end
      end

    billing_line =
      if billing_address_updated?(fields) do
        case Addresses.format_billing(job) do
          nil -> nil
          billing when billing in ["", "—"] -> nil
          billing -> "Updated #{short_client(job)}'s billing address to #{billing}."
        end
      end

    [service_line, billing_line]
  end

  defp apply_address_confirmations(assistant, ""), do: assistant

  defp apply_address_confirmations(assistant, address_confirmation) do
    assistant = String.trim(assistant)

    cond do
      assistant == "" ->
        address_confirmation

      address_focused_reply?(assistant) ->
        address_confirmation

      true ->
        String.trim("#{assistant} #{address_confirmation}")
    end
  end

  defp address_focused_reply?(text) when is_binary(text) do
    t = String.downcase(text)

    mentions_address? =
      String.contains?(t, "address") or String.contains?(t, "billing")

    mentions_other_fields? =
      Enum.any?(~w(phone email work description note material photo reminder), fn word ->
        String.contains?(t, word)
      end)

    mentions_address? and not mentions_other_fields?
  end

  defp address_focused_reply?(_), do: false

  defp normalize_field_names(fields) when is_list(fields) do
    Enum.map(fields, fn field -> field |> to_string() |> String.downcase() end)
  end

  defp normalize_field_names(_), do: []

  defp service_address_updated?(fields) do
    Enum.any?(@service_address_fields, &(&1 in fields))
  end

  defp billing_address_updated?(fields) do
    Enum.any?(@billing_address_fields, &(&1 in fields))
  end

  defp blank_address?(value) when is_binary(value), do: value in ["", "—"]
  defp blank_address?(_), do: true
end
