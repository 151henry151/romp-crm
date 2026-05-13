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

    failure_ct =
      Enum.count(results, fn r ->
        match?({:skipped, _}, r) or match?({:error, _}, r)
      end)

    base =
      cond do
        failure_ct > 0 and summary != "" ->
          summary

        is_binary(assistant_sms) and String.trim(assistant_sms) != "" ->
          String.trim(assistant_sms)

        summary != "" ->
          summary

        true ->
          if failure_ct > 0, do: "Some updates couldn't be applied—open Romp CRM.", else: "Done."
      end

    base |> merge_with_failures(failure_ct) |> truncate()
  end

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
