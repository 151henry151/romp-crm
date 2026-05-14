defmodule RompCrm.Reminders.Reminder do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending sent cancelled)

  schema "reminders" do
    belongs_to :user, RompCrm.Accounts.User
    belongs_to :business, RompCrm.Businesses.Business
    belongs_to :job, RompCrm.Jobs.Job

    field :body, :string
    field :fire_at, :utc_datetime
    field :status, :string, default: "pending"
    field :source, :string
    field :metadata_json, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:user_id, :business_id, :job_id, :body, :fire_at, :status, :source, :metadata_json])
    |> validate_required([:user_id, :business_id, :body, :fire_at])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:business_id)
    |> foreign_key_constraint(:job_id)
  end

  def user_update_changeset(%__MODULE__{} = reminder, attrs) when is_map(attrs) do
    reminder
    |> cast(attrs, [:body, :fire_at, :status])
    |> validate_required([:body, :fire_at])
    |> validate_inclusion(:status, @statuses)
  end
end
