# Renames duplicate client_name rows in a demo workspace (keeps lowest job id per name).
#
#   DATABASE_PATH=/home/henry/romp-crm/data/romp_crm.db MIX_ENV=prod env -u PHX_SERVER mix run scripts/dedupe_demo_workspace.exs

alias RompCrm.{Accounts, Jobs, Repo}

import Ecto.Query

email = System.get_env("DEMO_USER_EMAIL", "henry@romp.work")

user = Accounts.get_user_by_email(email) || raise "No user #{email}"

business_id =
  from(m in RompCrm.Businesses.BusinessMembership,
    join: b in RompCrm.Businesses.Business,
    on: b.id == m.business_id,
    where: m.user_id == ^user.id,
    order_by: [asc: b.name],
    select: b.id,
    limit: 1
  )
  |> Repo.one!()

replacement_names = [
  "William Walsh",
  "Elizabeth Morrison",
  "Joseph Richardson",
  "Margaret Elliott",
  "Charles Hammond",
  "Barbara Knox",
  "Thomas Prescott",
  "Dorothy Lane",
  "Richard Osborne",
  "Helen Granger",
  "Arthur Whitcomb",
  "Ruth Caldwell",
  "Henry Langford",
  "Florence Merritt",
  "Edward Holloway",
  "Virginia Shaw",
  "George Thornton",
  "Alice Pemberton",
  "Walter Cranston",
  "Eleanor Dunbar",
  "Raymond Keats",
  "Catherine Aldridge",
  "Benjamin Porter",
  "Grace Whitfield",
  "Samuel Harrington"
]

unique_email = fn name, job_id ->
  case String.split(name, " ", parts: 2) do
    [first, last] ->
      base = "#{String.downcase(first)}.#{String.downcase(last)}#{rem(job_id, 97)}"
      "#{base}@email.com"

    _ ->
      nil
  end
end

jobs =
  from(j in RompCrm.Jobs.Job,
    where: j.business_id == ^business_id,
    order_by: [asc: j.client_name, asc: j.id]
  )
  |> Repo.all()

used_names = MapSet.new(Enum.map(jobs, & &1.client_name))

available =
  replacement_names
  |> Enum.reject(&MapSet.member?(used_names, &1))

dupes =
  jobs
  |> Enum.group_by(& &1.client_name)
  |> Enum.flat_map(fn {_name, [_first | rest]} -> rest end)

if dupes == [] do
  IO.puts("Business #{business_id}: no duplicate client names found.")
else
  if length(dupes) > length(available) do
    raise "Need #{length(dupes)} replacement names, only #{length(available)} available"
  end

  renames =
    dupes
    |> Enum.with_index()
    |> Enum.map(fn {job, idx} ->
      new_name = Enum.at(available, idx)
      new_email = unique_email.(new_name, job.id)

      attrs =
        if is_binary(job.client_email) and job.client_email != "" do
          %{client_name: new_name, client_email: new_email}
        else
          %{client_name: new_name}
        end

      {:ok, _} = Jobs.update_job(job, attrs)
      {job.id, job.client_name, new_name}
    end)

  IO.puts("Business #{business_id}: renamed #{length(renames)} duplicate jobs")

  Enum.each(renames, fn {id, old, new} ->
    IO.puts("  ##{id} #{old} -> #{new}")
  end)
end

remaining_dupes =
  from(j in RompCrm.Jobs.Job,
    where: j.business_id == ^business_id,
    group_by: j.client_name,
    having: count(j.id) > 1,
    select: j.client_name
  )
  |> Repo.all()

if remaining_dupes == [] do
  IO.puts("OK: no duplicate client names remain (#{length(jobs)} jobs).")
else
  IO.puts("WARNING: still duplicated: #{inspect(remaining_dupes)}")
end
