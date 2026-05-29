defmodule RompCrm.Twilio.SmsReplyBuilder do
  @moduledoc """
  Builds short SMS confirmations from CRM operation outcomes.

  Keeps copy under ~300 characters when possible.
  """

  alias RompCrm.Jobs.Job
  alias RompCrm.Reminders.Reminder

  @max_len 320

  @doc """
  `results` is a list of `{:created, %Job{}}`, `{:updated, %Job{}, [field]}`,
  `{:skipped, atom}`, `{:error, atom}` in order.
  """
  def compose(assistant_sms \\ nil, results) when is_list(results) do
    summary = summarize_results(results)
    assistant = assistant_sms |> to_string() |> String.trim()

    failure_ct =
      Enum.count(results, fn r ->
        match?({:skipped, _}, r) or match?({:error, _}, r)
      end)

    base =
      cond do
        failure_ct > 0 and summary != "" ->
          summary

        photos_saved?(results) and clarifying_assistant_sms?(assistant) and summary != "" ->
          summary

        assistant != "" ->
          assistant

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
end
