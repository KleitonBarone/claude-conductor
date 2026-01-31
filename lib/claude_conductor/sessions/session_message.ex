defmodule ClaudeConductor.Sessions.SessionMessage do
  @moduledoc """
  Schema for session messages - conversation history within a session.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "session_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :session, ClaudeConductor.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  @roles ~w(user assistant system tool)

  @required_fields [:role, :content, :session_id]
  @optional_fields [:metadata]

  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:session_id)
  end

  def roles, do: @roles
end
