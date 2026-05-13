defmodule RompCrm.Reminders.JobReminderSendLog do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "job_reminder_send_logs" do
    belongs_to :user, RompCrm.Accounts.User
    belongs_to :job, RompCrm.Jobs.Job

    field :kind, :string
    field :anchor_on, :date

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:user_id, :job_id, :kind, :anchor_on])
    |> validate_required([:user_id, :job_id, :kind, :anchor_on])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:job_id)
    |> unique_constraint([:user_id, :job_id, :kind, :anchor_on],
          name: :job_reminder_send_logs_user_job_kind_anchor_unique
        )
  end
end
