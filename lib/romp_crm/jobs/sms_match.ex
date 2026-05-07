defmodule RompCrm.Jobs.SmsMatch do
  @moduledoc """
  Scores how well an existing `Job` matches SMS-derived clues from Claude.

  Used to pick a single job for PATCH-style SMS updates (address/name corrections, etc.).
  """

  alias RompCrm.Jobs.Job

  @doc """
  Non-negative score; higher means stronger match. Multiple weak hints can combine.
  """
  def score(%Job{} = job, spec) when is_map(spec) do
    spec = stringify(spec)

    # Work descriptions must score high enough alone to pass `sms_match_min_score/0` when the SMS
    # references the job only by task ("the water shutoff guy…") with no name or address snippet.
    0
    |> add_client_name(job.client_name, Map.get(spec, "client_name"))
    |> add_substring_field(job.address, Map.get(spec, "address_snippet"), 38)
    |> add_work_description_substring_field(
      job.work_description,
      Map.get(spec, "work_description_snippet"),
      48
    )
    |> add_substring_field(job.notes, Map.get(spec, "notes_snippet"), 18)
    |> add_phone_fragment(job.phone, Map.get(spec, "phone_fragment"))
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp add_client_name(acc, job_val, spec_val) do
    acc + client_name_points(blank_to_nil(job_val), blank_to_nil(spec_val))
  end

  defp blank_to_nil(v) when v in [nil, ""], do: nil

  defp blank_to_nil(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      s -> s
    end
  end

  defp blank_to_nil(v),
    do: v |> to_string() |> String.trim() |> then(fn s -> if s == "", do: nil, else: s end)

  defp client_name_points(nil, _), do: 0
  defp client_name_points(_, nil), do: 0

  defp client_name_points(job_cn, spec_cn) do
    j = String.downcase(job_cn)
    s = String.downcase(spec_cn)

    cond do
      j == s ->
        120

      String.contains?(j, s) and String.length(s) >= 4 ->
        78

      String.contains?(j, s) ->
        52

      String.contains?(s, j) and String.length(j) >= 4 ->
        62

      String.contains?(s, j) ->
        40

      true ->
        0
    end
  end

  defp add_substring_field(acc, _job_val, nil, _weight), do: acc

  defp add_substring_field(acc, job_val, spec_needle, weight) do
    case blank_to_nil(spec_needle) do
      nil -> acc
      needle -> acc + substring_points(blank_to_nil(job_val), needle, weight)
    end
  end

  # Claude often emits "water shut off" while techs type "water shutoff". Normalize trivial splits
  # so substring matching still lines up with stored CRM text.
  defp add_work_description_substring_field(acc, _job_val, nil, _weight), do: acc

  defp add_work_description_substring_field(acc, job_val, spec_needle, weight) do
    case blank_to_nil(spec_needle) do
      nil ->
        acc

      needle ->
        acc +
          substring_points_normalized(
            normalize_work_match_text(blank_to_nil(job_val)),
            normalize_work_match_text(needle),
            weight
          )
    end
  end

  defp normalize_work_match_text(nil), do: nil

  defp normalize_work_match_text(s) when is_binary(s) do
    s
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[\-_]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace("shut off", "shutoff")
  end

  defp substring_points_normalized(nil, _, _), do: 0
  defp substring_points_normalized(_, nil, _), do: 0

  defp substring_points_normalized(h, n, weight) when is_binary(h) and is_binary(n) do
    n = String.trim(n)

    cond do
      n == "" ->
        0

      String.contains?(h, n) and String.length(n) >= 6 ->
        weight

      String.contains?(h, n) and String.length(n) >= 3 ->
        trunc(weight * 0.65)

      true ->
        0
    end
  end

  defp substring_points(nil, _, _), do: 0

  defp substring_points(haystack, needle, weight) do
    h = String.downcase(haystack)
    n = String.downcase(String.trim(needle))

    cond do
      n == "" ->
        0

      String.contains?(h, n) and String.length(n) >= 6 ->
        weight

      String.contains?(h, n) and String.length(n) >= 3 ->
        trunc(weight * 0.65)

      true ->
        0
    end
  end

  defp add_phone_fragment(acc, nil, _), do: acc
  defp add_phone_fragment(acc, _, nil), do: acc

  defp add_phone_fragment(acc, job_phone, fragment) do
    case blank_to_nil(fragment) do
      nil ->
        acc

      frag ->
        digits_job = digits_only(job_phone)
        digits_frag = digits_only(frag)

        cond do
          digits_frag == "" ->
            acc

          String.ends_with?(digits_job, digits_frag) or String.contains?(digits_job, digits_frag) ->
            acc + 45

          true ->
            acc
        end
    end
  end

  defp digits_only(nil), do: ""
  defp digits_only(s) when is_binary(s), do: String.replace(s, ~r/\D/, "")
end
