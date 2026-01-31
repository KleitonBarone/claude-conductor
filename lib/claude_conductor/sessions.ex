defmodule ClaudeConductor.Sessions do
  @moduledoc """
  The Sessions context manages Claude Code CLI sessions and their messages.
  """

  import Ecto.Query
  alias ClaudeConductor.Repo
  alias ClaudeConductor.Sessions.{Session, SessionMessage}

  # ─────────────────────────────────────────────────────────────
  # Sessions
  # ─────────────────────────────────────────────────────────────

  def list_sessions(task_id) do
    Session
    |> where(task_id: ^task_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_session!(id) do
    Repo.get!(Session, id)
  end

  def get_session_with_messages!(id) do
    Session
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in SessionMessage, order_by: m.inserted_at))
  end

  def get_latest_session(task_id) do
    Session
    |> where(task_id: ^task_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def get_running_session(task_id) do
    Session
    |> where(task_id: ^task_id, status: "running")
    |> limit(1)
    |> Repo.one()
  end

  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  def start_session(%Session{} = session) do
    update_session(session, %{
      status: "running",
      started_at: DateTime.utc_now()
    })
  end

  def complete_session(%Session{} = session, exit_code) do
    update_session(session, %{
      status: if(exit_code == 0, do: "completed", else: "failed"),
      finished_at: DateTime.utc_now(),
      exit_code: exit_code
    })
  end

  # ─────────────────────────────────────────────────────────────
  # Session Messages
  # ─────────────────────────────────────────────────────────────

  def list_messages(session_id) do
    SessionMessage
    |> where(session_id: ^session_id)
    |> order_by(:inserted_at)
    |> Repo.all()
  end

  def create_message(attrs \\ %{}) do
    %SessionMessage{}
    |> SessionMessage.changeset(attrs)
    |> Repo.insert()
  end

  def add_user_message(session_id, content, metadata \\ %{}) do
    create_message(%{
      session_id: session_id,
      role: "user",
      content: content,
      metadata: metadata
    })
  end

  def add_assistant_message(session_id, content, metadata \\ %{}) do
    create_message(%{
      session_id: session_id,
      role: "assistant",
      content: content,
      metadata: metadata
    })
  end

  def add_tool_message(session_id, content, metadata \\ %{}) do
    create_message(%{
      session_id: session_id,
      role: "tool",
      content: content,
      metadata: metadata
    })
  end
end
