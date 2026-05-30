# Seeds pending reminders for demo / screenshot use.
#
#   DATABASE_PATH=/home/henry/romp-crm/data/romp_crm.db MIX_ENV=prod env -u PHX_SERVER mix run scripts/seed_demo_reminders.exs
#
# Optional: DEMO_USER_EMAIL=henry@romp.work  DEMO_MIN_PENDING=12

defmodule DemoWorkspaceReminders do
  import Ecto.Query

  alias RompCrm.{Accounts, Jobs, Reminders, Repo}
  alias RompCrm.Reminders.Reminder

  @tz "America/New_York"

  def run(user_id, business_id, opts \\ []) do
    min_pending = Keyword.get(opts, :min_pending, 12)

    pending_count =
      Repo.aggregate(
        from(r in Reminder,
          where: r.user_id == ^user_id,
          where: r.business_id == ^business_id,
          where: r.status == "pending"
        ),
        :count
      )

    if pending_count >= min_pending do
      IO.puts("Already have #{pending_count} pending reminders; skipping seed.")
      pending_count
    else
      jobs =
        Repo.all(
          from(j in Jobs.Job,
            where: j.business_id == ^business_id,
            order_by: [asc: j.id],
            limit: 20
          )
        )

      job_at = fn
        nil ->
          nil

        i ->
          case Enum.at(jobs, rem(i, max(length(jobs), 1))) do
            nil -> nil
            j -> j.id
          end
      end

      today = Date.utc_today()

      templates = [
        {0, "08:00", "Call supplier about water heater backorder", 0},
        {0, "14:30", "Pick up 50 gal heater at Ferguson — bring receipt book", nil},
        {1, "09:00", "Follow up with Dave Wohl on kitchen faucet estimate", 1},
        {1, "16:00", "Text Jimmy Wang when today's job wraps", 3},
        {2, "07:30", "Load van — wax rings, supply lines, shark bites", nil},
        {2, "10:00", "Confirm Mary Frank site visit time", 2},
        {3, "09:00", "Send invoice to Robert Brooks", 6},
        {3, "13:00", "Check permit status for Middlebury rough-in", 4},
        {4, "08:30", "Order Zoeller sump pump for Friday install", nil},
        {5, "09:00", "Call Greg Gorman about change order approval", 0},
        {5, "11:00", "Review open time entries before payroll", nil},
        {6, "09:00", "Schedule follow-up call — Nancy Bennett lead", 13},
        {7, "15:00", "Drop off keys at 112 Main St after inspection", 5},
        {8, "09:00", "Remind Mike to finish Bennett punch list", 12},
        {10, "09:00", "Restock van — PVC cement, Teflon tape, pipe dope", nil},
        {12, "10:30", "Call client re frozen pipe thaw — confirm access", 9},
        {14, "09:00", "Follow up on boiler tune-up parts quote", 7}
      ]

      created =
        Enum.reduce(templates, 0, fn {day_offset, time, body, job_idx}, acc ->
          date = Date.add(today, day_offset) |> Date.to_iso8601()

          case Reminders.compose_fire_at_utc(date, time, @tz, 9) do
            {:ok, fire_at} ->
              attrs = %{
                user_id: user_id,
                business_id: business_id,
                job_id: job_at.(job_idx),
                body: body,
                fire_at: fire_at,
                status: "pending",
                source: "web",
                metadata_json: Jason.encode!(%{demo_seed: true})
              }

              case Reminders.create_reminder(attrs) do
                {:ok, _} -> acc + 1
                {:error, cs} ->
                  IO.warn("Reminder insert failed: #{inspect(cs.errors)}")
                  acc
              end

            :error ->
              IO.warn("Bad fire_at for #{date} #{time}")
              acc
          end
        end)

      IO.puts("Created #{created} pending reminders (#{pending_count} existed).")
      created + pending_count
    end
  end

  def run_for_email(email \\ "henry@romp.work", opts \\ []) do
    import Ecto.Query

    alias RompCrm.Repo

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

    IO.puts("Seeding reminders for #{email} business_id=#{business_id}")
    run(user.id, business_id, opts)
  end
end

unless System.get_env("DEMO_REMINDERS_DEFINE_ONLY") == "1" do
  email = System.get_env("DEMO_USER_EMAIL", "henry@romp.work")
  min_pending = System.get_env("DEMO_MIN_PENDING", "12") |> String.to_integer()
  DemoWorkspaceReminders.run_for_email(email, min_pending: min_pending)
end
