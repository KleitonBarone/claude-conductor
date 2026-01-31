defmodule ClaudeConductor.Projects.Task do
  @moduledoc """
  Schema for tasks - units of work within a project.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :prompt, :string
    field :status, :string, default: "pending"
    field :position, :integer, default: 0

    belongs_to :project, ClaudeConductor.Projects.Project
    has_many :sessions, ClaudeConductor.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(pending running completed failed cancelled)

  @required_fields [:title, :project_id]
  @optional_fields [:prompt, :status, :position]

  def changeset(task, attrs) do
    task
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end

  def statuses, do: @statuses
end
