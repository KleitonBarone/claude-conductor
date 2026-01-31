defmodule ClaudeConductor.Sessions.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing SessionServer processes.

  Each SessionServer wraps a Claude Code CLI process via Port.
  Sessions are identified by their database session_id and registered
  in SessionRegistry for lookup.
  """

  use DynamicSupervisor

  alias ClaudeConductor.Sessions.{SessionServer, SessionRegistry}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new SessionServer for the given session.

  The session must already exist in the database.

  ## Options

  - `:session_id` - Required. The database session ID.

  ## Returns

  - `{:ok, pid}` on success
  - `{:error, {:already_started, pid}}` if session is already running
  - `{:error, reason}` on failure
  """
  def start_session(session_id, opts \\ []) do
    if SessionRegistry.running?(session_id) do
      {:ok, pid} = SessionRegistry.lookup(session_id)
      {:error, {:already_started, pid}}
    else
      spec = {SessionServer, [{:session_id, session_id} | opts]}
      DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  @doc """
  Stop a running session gracefully.

  Returns `:ok` on success, `{:error, :not_found}` if not running.
  """
  def stop_session(session_id) do
    case SessionRegistry.lookup(session_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  List all running session IDs.
  """
  def list_running do
    SessionRegistry.list_all()
  end

  @doc """
  Count of currently running sessions.
  """
  def count_running do
    length(list_running())
  end
end
