defmodule ClaudeConductor.Projects.Project do
  @moduledoc """
  Schema for projects - a codebase that contains tasks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string
    field :description, :string
    field :path, :string
    field :status, :string, default: "active"

    has_many :tasks, ClaudeConductor.Projects.Task
    has_many :context_files, ClaudeConductor.Context.ContextFile

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :path]
  @optional_fields [:description, :status]

  def changeset(project, attrs) do
    project
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(active archived))
    |> unique_constraint(:path)
  end
end
