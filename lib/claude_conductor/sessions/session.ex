defmodule ClaudeConductor.Sessions.Session do
  @moduledoc """
  Schema for sessions - an LLM execution for a task.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :status, :string, default: "idle"
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :exit_code, :integer
    field :provider, :string
    field :model, :string
    field :request_id, :string
    field :usage, :map, default: %{}

    belongs_to :task, ClaudeConductor.Projects.Task
    has_many :messages, ClaudeConductor.Sessions.SessionMessage

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(idle starting running completed failed)

  @required_fields [:task_id]
  @optional_fields [
    :status,
    :started_at,
    :finished_at,
    :exit_code,
    :provider,
    :model,
    :request_id,
    :usage
  ]

  def changeset(session, attrs) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:task_id)
  end

  def statuses, do: @statuses
end
