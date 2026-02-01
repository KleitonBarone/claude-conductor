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

  def get_session(id) do
    case Repo.get(Session, id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
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

  @doc """
  Reset orphaned sessions and their associated tasks.

  Called on application startup to clean up sessions that were marked as "running"
  but have no corresponding process (e.g., after a crash or restart).

  Also resets any tasks marked as "running" since no task should be running
  without an active process.

  Returns the number of sessions that were reset.
  """
  def reset_orphaned_sessions do
    alias ClaudeConductor.Projects.Task

    now = DateTime.utc_now()

    # Reset orphaned sessions
    {session_count, _} =
      Session
      |> where([s], s.status == "running")
      |> Repo.update_all(
        set: [status: "failed", exit_code: -1, finished_at: now, updated_at: now]
      )

    # Reset ALL tasks that are marked as running
    # (since no process should be running at startup)
    {task_count, _} =
      Task
      |> where([t], t.status == "running")
      |> Repo.update_all(set: [status: "failed", updated_at: now])

    if task_count > 0 do
      require Logger
      Logger.info("Reset #{task_count} orphaned task(s) on startup")
    end

    session_count
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

  # ─────────────────────────────────────────────────────────────
  # Session Execution (via SessionServer)
  # ─────────────────────────────────────────────────────────────

  alias ClaudeConductor.Sessions.{SessionSupervisor, SessionServer, SessionRegistry}

  @doc """
  Start executing a session with Claude Code CLI.

  Creates a SessionServer process that manages the CLI interaction.
  The session must already exist in the database.

  ## Returns

  - `{:ok, pid}` on success
  - `{:error, {:already_started, pid}}` if already running
  - `{:error, reason}` on failure
  """
  def run_session(session_id) do
    SessionSupervisor.start_session(session_id)
  end

  @doc """
  Stop a running session gracefully.
  """
  def stop_running_session(session_id) do
    SessionServer.stop(session_id)
  end

  @doc """
  Check if a session is currently being executed.
  """
  def session_running?(session_id) do
    SessionRegistry.running?(session_id)
  end

  @doc """
  Get the execution status of a session.

  Returns `:starting`, `:running`, `:stopping`, or `:not_running`.
  """
  def get_execution_status(session_id) do
    SessionServer.get_status(session_id)
  end

  @doc """
  List all currently running session IDs.
  """
  def list_running_sessions do
    SessionSupervisor.list_running()
  end

  @doc """
  Create a session and immediately start running it.

  Convenience function that combines create_session and run_session.
  """
  def create_and_run_session(attrs) do
    with {:ok, session} <- create_session(attrs),
         {:ok, pid} <- run_session(session.id) do
      {:ok, session, pid}
    end
  end
end
