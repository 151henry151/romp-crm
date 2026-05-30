# Seeds realistic demo data for screenshot / demo use.
#
#   DATABASE_PATH=/home/henry/romp-crm/data/romp_crm.db MIX_ENV=prod mix run scripts/seed_demo_workspace.exs
#
# Optional: DEMO_USER_EMAIL=henry@romp.work

alias RompCrm.{Accounts, Employees, Jobs, Repo, TimeTracking}

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

IO.puts("Seeding demo data for #{email} business_id=#{business_id}")

vt_towns = [
  {"Burlington", "VT", "05401"},
  {"Middlebury", "VT", "05753"},
  {"Rutland", "VT", "05701"},
  {"Montpelier", "VT", "05602"},
  {"Stowe", "VT", "05672"},
  {"Bennington", "VT", "05201"},
  {"Brattleboro", "VT", "05301"},
  {"Williston", "VT", "05495"},
  {"Essex Junction", "VT", "05452"},
  {"Colchester", "VT", "05446"}
]

streets = [
  "42 Maple St",
  "18 Pine Ridge Rd",
  "5 South St",
  "112 Main St",
  "34 Exchange St",
  "7 Lakeview Dr",
  "256 College St",
  "89 Elmwood Ave",
  "3 Quarry Hill Ln",
  "61 River Rd"
]

first_names = ~w(Patricia Robert Linda Michael Susan James Karen Daniel Nancy Mark William Elizabeth Joseph Margaret Charles Barbara Thomas Dorothy Richard Helen Arthur Ruth Henry Florence Edward Virginia George Alice Walter Eleanor Raymond Catherine Benjamin Grace Samuel Theresa Frank Olivia Peter Janet Gloria Nathan Sylvia Curtis Anita Victor Claire Harold Bonnie)
last_names = ~w(Carter Brooks Nguyen Patel Sullivan Reed Foster Hayes Bennett Coleman Walsh Morrison Richardson Elliott Hammond Knox Prescott Lane Osborne Granger Whitcomb Caldwell Langford Merritt Holloway Shaw Thornton Pemberton Cranston Dunbar Keats Aldridge Porter Whitfield Harrington Lombard Delaney Marsh Sinclair Vogt Finch Pierce Grant Boone Rhodes Lang Dunst Meacham Carver)

work_templates = [
  {"Water heater replacement", ["Drain and remove old tank", "Install 50 gal gas water heater", "Test T&P and venting"],
   ["50 gal water heater", "Expansion tank", "Ball valves", "Gas flex line"]},
  {"Kitchen faucet swap", ["Shut off under-sink valves", "Remove old faucet", "Install Moen pull-down"],
   ["Kitchen faucet", "Supply lines", "Plumber's putty"]},
  {"Toilet replacement", ["Remove old toilet", "Reset flange and wax ring", "Install elongated toilet"],
   ["Elongated toilet", "Wax ring", "Brass closet bolts"]},
  {"Clogged drain", ["Snake kitchen line", "Flush with hot water", "Check cleanout"],
   ["Drain snake rental", "Bio-clean"]},
  {"Sump pump install", ["Dig pit if needed", "Install Zoeller M53", "Run discharge line"],
   ["Sump pump", "Check valve", "PVC 1.5\" pipe"]},
  {"Boiler tune-up", ["Combustion test", "Clean burner", "Check circulator"],
   ["Nozzle", "Oil filter", "Gauge glass"]},
  {"Gas line for stove", ["Run 1/2\" black pipe", "Install shutoff", "Leak test"],
   ["Black iron pipe", "Gas shutoff valve", "Pipe dope"]},
  {"Shower valve repair", ["Open wall access", "Replace cartridge", "Silicone trim"],
   ["Shower cartridge", "Silicone caulk"]},
  {"Whole-house filter", ["Install filter housing", "Add bypass", "Flush system"],
   ["Filter housing", "Sediment filters", "Mounting bracket"]},
  {"Frozen pipe thaw", ["Locate freeze", "Thaw with heat tape", "Insulate exposed run"],
   ["Heat tape", "Pipe insulation"]}
]

statuses = [
  :lead,
  :lead,
  :lead,
  :lead,
  :lead,
  :lead,
  :lead,
  :lead,
  :pending,
  :pending,
  :pending,
  :pending,
  :pending,
  :pending,
  :pending,
  :pending,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :in_progress,
  :done,
  :done,
  :done,
  :done,
  :done,
  :done,
  :done,
  :done,
  :done
]

seed_jobs =
  Enum.with_index(statuses, 1)
  |> Enum.map(fn {status, i} ->
    {city, state, zip} = Enum.at(vt_towns, rem(i, length(vt_towns)))
    street = Enum.at(streets, rem(i, length(streets)))
    fname = Enum.at(first_names, rem(i - 1, length(first_names)))
    lname = Enum.at(last_names, rem(i - 1, length(last_names)))

    {work_desc, tasks, mats} = Enum.at(work_templates, rem(i, length(work_templates)))

    sparse? = rem(i, 7) == 0
    minimal? = rem(i, 11) == 0

    phone =
      if minimal? do
        nil
      else
        "+1802#{String.pad_leading(Integer.to_string(200_0000 + i * 173), 7, "0")}"
      end

    client_email =
      if sparse? or minimal? do
        nil
      else
        "#{String.downcase(fname)}.#{String.downcase(lname)}#{rem(i, 99)}@email.com"
      end

    address_attrs =
      if minimal? do
        %{address: "#{street}, #{city} #{state}"}
      else
        %{
          address_line1: street,
          city: city,
          state: state,
          postal_code: zip
        }
      end

    priority = if rem(i, 9) == 0, do: :high, else: :normal

    scheduled_on =
      case status do
        :lead -> if sparse?, do: nil, else: Date.add(Date.utc_today(), rem(i, 21) + 3)
        :pending -> Date.add(Date.utc_today(), rem(i, 10) + 1)
        :in_progress -> Date.add(Date.utc_today(), rem(i, 5))
        :done -> Date.add(Date.utc_today(), -(rem(i, 14) + 2))
      end

    work_items =
      tasks
      |> Enum.with_index()
      |> Enum.map(fn {title, wi_i} ->
        completed? =
          status == :done or
            (status == :in_progress and wi_i == 0) or
            (status == :in_progress and rem(i, 3) == 0 and wi_i <= 1)

        %{
          title: title,
          sort_order: wi_i,
          scheduled_on: scheduled_on,
          completed: completed?
        }
      end)

    materials =
      if minimal? do
        []
      else
        mats
        |> Enum.with_index()
        |> Enum.map(fn {desc, mi} ->
          %{
            description: desc,
            quantity: if(rem(mi, 2) == 0, do: 1, else: 2),
            sort_order: mi,
            completed: status == :done or (status == :in_progress and mi == 0)
          }
        end)
      end

    notes =
      cond do
        minimal? -> nil
        status == :lead -> "Called from voicemail — needs callback"
        status == :pending -> "Parts on truck; confirm morning of"
        status == :in_progress -> "Customer home until noon"
        status == :done -> "Invoiced; check paid"
      end

    next_action =
      cond do
        status == :done -> nil
        sparse? -> "Call to confirm"
        true -> Enum.at(["Schedule visit", "Order parts", "Send estimate", "Follow up text"], rem(i, 4))
      end

    referred_by =
      if rem(i, 6) == 0 do
        "Neighbor referral"
      else
        if sparse?, do: nil, else: Enum.at(["Google", "Angi", "Repeat customer", nil], rem(i, 4))
      end

    %{
      business_id: business_id,
      client_name: "#{fname} #{lname}",
      status: status,
      priority: priority,
      work_description: work_desc,
      phone: phone,
      client_email: client_email,
      notes: notes,
      next_action: next_action,
      referred_by: referred_by,
      scheduled_on: scheduled_on,
      work_items: work_items,
      materials: materials
    }
    |> Map.merge(address_attrs)
  end)

created_jobs =
  Enum.map(seed_jobs, fn attrs ->
    case Jobs.create_job(attrs) do
      {:ok, job} ->
        job

      {:error, cs} ->
        IO.warn("Failed job #{attrs.client_name}: #{inspect(cs.errors)}")
        nil
    end
  end)
  |> Enum.reject(&is_nil/1)

IO.puts("Created #{length(created_jobs)} jobs")

employee_specs = [
  %{name: "Mike Torres", title: "Journeyman plumber", phone: "+18025550191", email: "mike.torres@romp.work", can_edit_jobs: true, can_log_job_time: true, can_log_employee_time_for_others: true},
  %{name: "Sarah Chen", title: "Apprentice", phone: "+18025550234", email: "sarah.chen@romp.work", can_edit_jobs: false, can_log_job_time: true}
]

employees =
  Enum.map(employee_specs, fn spec ->
    existing =
      Repo.one(
        from e in RompCrm.Employees.Employee,
          where: e.business_id == ^business_id and e.name == ^spec.name,
          limit: 1
      )

    if existing do
      existing
    else
      {:ok, emp} = Employees.create_employee(Map.put(spec, :business_id, business_id))
      emp
    end
  end)

IO.puts("Employees: #{Enum.map(employees, & &1.name) |> Enum.join(", ")}")

# Job time entries (closed) on in_progress and done jobs
job_time_targets =
  created_jobs
  |> Enum.filter(&(&1.status in [:in_progress, :done]))
  |> Enum.take(12)

job_time_count =
  Enum.with_index(job_time_targets, 1)
  |> Enum.reduce(0, fn {job, n}, acc ->
    day_offset = rem(n, 10) + 1
    start = NaiveDateTime.new!(Date.add(Date.utc_today(), -day_offset), ~T[08:30:00])
    finish = NaiveDateTime.add(start, 2 * 3600 + rem(n, 5) * 900)

    case TimeTracking.create_time_entry(%{
           business_id: business_id,
           job_id: job.id,
           started_at: start,
           ended_at: finish,
           notes: if(rem(n, 3) == 0, do: "With #{Enum.at(employees, 0).name}", else: nil)
         }) do
      {:ok, _} -> acc + 1
      {:error, _} -> acc
    end
  end)

# One open job clock on an in_progress job
open_job =
  created_jobs |> Enum.find(&(&1.status == :in_progress))

if open_job do
  TimeTracking.create_time_entry(%{
    business_id: business_id,
    job_id: open_job.id,
    started_at: NaiveDateTime.new!(Date.utc_today(), ~T[09:15:00])
  })
end

IO.puts("Job time entries: #{job_time_count} closed" <> if(open_job, do: " + 1 open", else: ""))

# Employee workday punches — last 2 weeks
emp_punch_count =
  Enum.reduce(0..9, 0, fn day_back, acc ->
    date = Date.add(Date.utc_today(), -day_back)

    if Date.day_of_week(date) in 1..5 do
      Enum.with_index(employees)
      |> Enum.reduce(acc, fn {emp, emp_i}, inner ->
        in_at = NaiveDateTime.new!(date, Time.add(~T[07:30:00], emp_i * 900))
        lunch_start = NaiveDateTime.new!(date, ~T[12:00:00])
        lunch_end = NaiveDateTime.new!(date, ~T[12:30:00])
        out_at = NaiveDateTime.new!(date, Time.add(~T[16:00:00], emp_i * 600))

        open_today? = day_back == 0 and emp_i == 0

        attrs = %{
          business_id: business_id,
          employee_id: emp.id,
          clocked_in_at: in_at,
          lunch_start_at: lunch_start,
          lunch_end_at: lunch_end,
          clock_in_kind: :live_punch,
          clock_out_kind: if(open_today?, do: nil, else: :live_punch)
        }

        attrs =
          if open_today? do
            Map.drop(attrs, [:clocked_out_at, :clock_out_kind])
          else
            Map.put(attrs, :clocked_out_at, out_at)
          end

        case Employees.create_time_entry(attrs) do
          {:ok, _} -> inner + 1
          {:error, _} -> inner
        end
      end)
    else
      acc
    end
  end)

IO.puts("Employee timeclock punches: #{emp_punch_count}")

System.put_env("DEMO_REMINDERS_DEFINE_ONLY", "1")
Code.require_file(Path.join(__DIR__, "seed_demo_reminders.exs"))
System.delete_env("DEMO_REMINDERS_DEFINE_ONLY")
reminder_total = DemoWorkspaceReminders.run(user.id, business_id)

total =
  Repo.aggregate(from(j in RompCrm.Jobs.Job, where: j.business_id == ^business_id), :count)

IO.puts("Done. Business #{business_id} now has #{total} jobs and #{reminder_total} pending reminders.")
