defmodule ClaudeConductor.Context.ContextFile do
  @moduledoc """
  Schema for context files - project files included in session context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "context_files" do
    field :path, :string
    field :included, :boolean, default: true
    field :file_type, :string
    field :last_modified, :utc_datetime

    belongs_to :project, ClaudeConductor.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @required_fields [:path, :project_id]
  @optional_fields [:included, :file_type, :last_modified]

  def changeset(context_file, attrs) do
    context_file
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:project_id, :path])
  end
end
