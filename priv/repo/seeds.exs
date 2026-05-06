alias JgsCrm.Repo
alias JgsCrm.Jobs.Job

jobs = [
  %{
    client_name: "Angela Brande",
    work_description: "Continue basement project",
    priority: :normal,
    status: :in_progress
  },
  %{
    client_name: "Bud Reed",
    work_description: "Water shutoff",
    priority: :normal,
    status: :pending
  },
  %{
    client_name: "Hector Vila",
    work_description: "Floor under refrigerator; paint house (TBD)?",
    priority: :normal,
    status: :in_progress
  },
  %{
    client_name: "Tom Van Order",
    work_description: "Sump pump hard pipe",
    priority: :normal,
    status: :pending
  },
  %{
    client_name: "Cheryl Kater",
    work_description: "Fix ceiling",
    priority: :normal,
    status: :in_progress
  },
  %{
    client_name: "Unnamed",
    address: "High Street",
    work_description: "Sump pump hard pipe",
    priority: :normal,
    status: :pending
  },
  %{
    client_name: "Danielle Rougeau",
    address: "Orwell, VT",
    work_description: "TBD",
    priority: :normal,
    status: :lead,
    referred_by: "Helen Freismuth",
    next_action: "Call to schedule"
  },
  %{
    client_name: "Miles Peterle",
    work_description: "Windows",
    priority: :normal,
    status: :lead,
    next_action: "Call to schedule"
  },
  %{
    client_name: "James Rd (McKenna neighbor)",
    address: "James Rd",
    work_description: "Oil tank",
    priority: :normal,
    status: :lead,
    next_action: "Call to schedule"
  },
  %{
    client_name: "MacArthur Stine",
    address: "32 Seminary St (corner Main & Seminary), Castleton, VT 05735",
    work_description:
      "Natural gas boiler → radiant floors + wall radiator + domestic HW. System underperforming; inline domestic filter leaks/needs replacement; boiler throwing errors; noisy pumps; erratic pressure (suspect bad expansion tank); silt/grit from Castleton town water; suspected leak in boiler flat pack.",
    priority: :high,
    status: :lead,
    referred_by: "Sara Grey",
    notes:
      "Works from home — flexible with lead time. Converted church / big treehouse. Pics to follow.",
    next_action: "Call; request pics"
  },
  %{
    client_name: "Cider Mill Rd",
    address: "Cider Mill Rd",
    work_description: "Spigot; water heater; two bathroom rough-ins (TBD?)",
    priority: :high,
    status: :lead,
    next_action: "Call to schedule"
  },
  %{
    client_name: "Carolyn Brewer",
    work_description: "Hand rail; insulation; redo lower bathroom drain; redo all drain plumbing",
    priority: :normal,
    status: :lead,
    next_action: "Call to schedule"
  },
  %{
    client_name: "Michal Woll",
    address: "1282 Painter Rd",
    phone: "414-294-9199",
    work_description: "Reroute laundry gray water into septic",
    priority: :normal,
    status: :lead,
    notes: "Works from home — flexible. Call came in Mon 5/4 7:55 AM.",
    next_action: "Visit Thu May 7"
  }
]

now = DateTime.utc_now() |> DateTime.truncate(:second)

Repo.insert_all(
  Job,
  Enum.map(jobs, fn job ->
    job
    |> Map.put_new(:address, nil)
    |> Map.put_new(:phone, nil)
    |> Map.put_new(:referred_by, nil)
    |> Map.put_new(:notes, nil)
    |> Map.put_new(:next_action, nil)
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end)
)

IO.puts("Seeded #{length(jobs)} jobs.")
