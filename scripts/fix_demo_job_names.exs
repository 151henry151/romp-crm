# Fixes demo jobs given broken single-word names after a bad dedupe run.
#
#   DATABASE_PATH=/home/henry/romp-crm/data/romp_crm.db MIX_ENV=prod env -u PHX_SERVER mix run scripts/fix_demo_job_names.exs

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

fixes = [
  {102, "William Walsh"},
  {103, "Elizabeth Morrison"},
  {104, "Joseph Richardson"},
  {105, "Margaret Elliott"},
  {106, "Charles Hammond"},
  {107, "Barbara Knox"},
  {108, "Thomas Prescott"},
  {109, "Dorothy Lane"},
  {110, "Richard Osborne"},
  {111, "Helen Granger"},
  {112, "Arthur Whitcomb"},
  {113, "Ruth Caldwell"},
  {114, "Henry Langford"},
  {115, "Florence Merritt"},
  {116, "Edward Holloway"},
  {117, "Virginia Shaw"},
  {118, "George Thornton"},
  {119, "Alice Pemberton"},
  {120, "Walter Cranston"},
  {121, "Eleanor Dunbar"},
  {122, "Raymond Keats"},
  {123, "Catherine Aldridge"},
  {124, "Benjamin Porter"},
  {125, "Grace Whitfield"},
  {126, "Samuel Harrington"}
]

Enum.each(fixes, fn {id, new_name} ->
  job = Jobs.get_job!(id, business_id)

  attrs =
    case String.split(new_name, " ", parts: 2) do
      [first, last] when is_binary(job.client_email) and job.client_email != "" ->
        email = "#{String.downcase(first)}.#{String.downcase(last)}#{rem(id, 97)}@email.com"
        %{client_name: new_name, client_email: email}

      _ ->
        %{client_name: new_name}
    end

  {:ok, _} = Jobs.update_job(job, attrs)
  IO.puts("##{id} -> #{new_name}")
end)

dupes =
  from(j in RompCrm.Jobs.Job,
    where: j.business_id == ^business_id,
    group_by: j.client_name,
    having: count(j.id) > 1,
    select: j.client_name
  )
  |> Repo.all()

if dupes == [] do
  IO.puts("OK: #{Repo.aggregate(from(j in RompCrm.Jobs.Job, where: j.business_id == ^business_id), :count)} jobs, all unique client names.")
else
  IO.puts("WARNING: duplicates remain: #{inspect(dupes)}")
end
