defmodule ClaudeConductor.Sessions.SessionServer do
  @moduledoc """
  GenServer that manages LLM session execution.

  ## Responsibilities

  - Executes prompt via configured LLM provider
  - Persists messages to database
  - Broadcasts updates via PubSub for LiveView
  - Handles graceful shutdown and error recovery

  ## Usage

      # Start via SessionSupervisor
      {:ok, pid} = SessionSupervisor.start_session(session_id)

      # Stop gracefully
      SessionServer.stop(session_id)

      # Check status
      SessionServer.get_status(session_id)
  """

  use GenServer
  require Logger

  alias ClaudeConductor.Sessions
  alias ClaudeConductor.Sessions.{SessionRegistry, Providers.OpenAICompatible}
  alias ClaudeConductor.Projects

  # ─────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: SessionRegistry.via(session_id))
  end

  def child_spec(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    %{
      id: {__MODULE__, session_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 10_000
    }
  end

  @doc """
  Request graceful stop of the session.
  """
  def stop(session_id) do
    GenServer.call(SessionRegistry.via(session_id), :stop)
  catch
    :exit, {:noproc, _} -> {:error, :not_running}
  end

  @doc """
  Get current session status.

  Returns `:starting`, `:running`, `:stopping`, or `:not_running`.
  """
  def get_status(session_id) do
    GenServer.call(SessionRegistry.via(session_id), :get_status)
  catch
    :exit, {:noproc, _} -> :not_running
  end

  # ─────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ─────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    provider_module_override = Keyword.get(opts, :provider_module)
    provider_config_override = Keyword.get(opts, :provider_config)
    Process.flag(:trap_exit, true)

    # Load session with associations
    session = Sessions.get_session!(session_id)
    task = Projects.get_task!(session.task_id)
    project = Projects.get_project!(task.project_id)

    state = %{
      session_id: session_id,
      session: session,
      task: task,
      project: project,
      request_pid: nil,
      request_ref: nil,
      status: :starting,
      provider_module_override: provider_module_override,
      provider_config_override: provider_config_override
    }

    {:ok, state, {:continue, :start_request}}
  end

  @impl true
  def handle_continue(:start_request, state) do
    {:ok, session} = Sessions.start_session(state.session)
    broadcast(state.session_id, :session_started, %{})

    {request_pid, request_ref} = spawn_request_worker(state)

    Logger.info("SessionServer started for session #{state.session_id}")

    {:noreply,
     %{
       state
       | session: session,
         request_pid: request_pid,
         request_ref: request_ref,
         status: :running
     }}
  end

  @impl true
  def handle_continue(:graceful_stop, %{request_pid: request_pid} = state)
      when is_pid(request_pid) do
    Process.exit(request_pid, :kill)
    complete_and_stop(state, 130, :normal)
  end

  def handle_continue(:graceful_stop, state) do
    complete_and_stop(state, 130, :normal)
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:reply, :ok, %{state | status: :stopping}, {:continue, :graceful_stop}}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:provider_result, {:ok, result}}, %{status: :running} = state) do
    new_state = persist_provider_success(state, result)
    complete_and_stop(new_state, 0, :normal)
  end

  def handle_info({:provider_result, {:error, reason}}, %{status: :running} = state) do
    Logger.error("Provider request failed for session #{state.session_id}: #{inspect(reason)}")
    broadcast(state.session_id, :session_failed, %{reason: reason})
    complete_and_stop(state, 1, :normal)
  end

  def handle_info({:provider_result, _result}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, request_ref, :process, request_pid, reason},
        %{request_ref: request_ref, request_pid: request_pid, status: :running} = state
      ) do
    case reason do
      :normal ->
        {:noreply, %{state | request_pid: nil, request_ref: nil}}

      _ ->
        Logger.error(
          "Provider worker crashed for session #{state.session_id}: #{inspect(reason)}"
        )

        broadcast(state.session_id, :session_failed, %{reason: :provider_crashed})
        complete_and_stop(%{state | request_pid: nil, request_ref: nil}, 1, :normal)
    end
  end

  def handle_info(msg, state) do
    Logger.debug("SessionServer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SessionServer terminating for session #{state.session_id}: #{inspect(reason)}")

    if is_pid(state.request_pid) do
      Process.exit(state.request_pid, :kill)
    end

    # Ensure session is marked as completed/failed if still running
    # Check database state, not cached state
    case Sessions.get_session(state.session_id) do
      {:ok, session} when session.status == "running" ->
        exit_code = if reason == :normal, do: 0, else: 1
        Sessions.complete_session(session, exit_code)
        # Also update the task status
        update_task_status(state.task, exit_code)
        broadcast(state.session_id, :session_terminated, %{reason: reason})

      _ ->
        :ok
    end

    :ok
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions - Session Completion
  # ─────────────────────────────────────────────────────────────

  defp complete_and_stop(state, exit_code, stop_reason) do
    {:ok, session} = Sessions.complete_session(state.session, exit_code)
    update_task_status(state.task, exit_code)
    broadcast(state.session_id, :session_completed, %{exit_code: exit_code})

    {:stop, stop_reason, %{state | request_pid: nil, request_ref: nil, session: session}}
  end

  defp update_task_status(task, exit_code) do
    new_status = if exit_code == 0, do: "completed", else: "failed"
    Projects.update_task_status(task, new_status)
  end

  defp spawn_request_worker(state) do
    parent = self()
    prompt = state.task.prompt || "Hello"
    provider_module = provider_module(state)
    config = provider_config(state)

    spawn_monitor(fn ->
      result = provider_module.complete(prompt, config: config)
      send(parent, {:provider_result, result})
    end)
  end

  defp provider_module(%{provider_module_override: module}) when is_atom(module), do: module

  defp provider_module(state) do
    state
    |> provider_config()
    |> Map.get(:provider_module, OpenAICompatible)
  end

  defp provider_config(%{provider_config_override: override}) when is_map(override) do
    Map.merge(Application.get_env(:claude_conductor, :llm, %{}), override)
  end

  defp provider_config(_state) do
    Application.get_env(:claude_conductor, :llm, %{})
  end

  defp persist_provider_success(state, result) do
    content = Map.get(result, :content, "")

    metadata =
      %{
        "provider" => Map.get(result, :provider),
        "model" => Map.get(result, :model),
        "request_id" => Map.get(result, :request_id),
        "usage" => Map.get(result, :usage, %{})
      }
      |> Enum.reject(fn {_k, value} -> is_nil(value) end)
      |> Map.new()

    if content != "" do
      {:ok, _message} = Sessions.add_assistant_message(state.session_id, content, metadata)
      broadcast(state.session_id, :message, %{role: "assistant", content: content})
    end

    session_attrs = %{
      provider: Map.get(result, :provider),
      model: Map.get(result, :model),
      request_id: Map.get(result, :request_id),
      usage: Map.get(result, :usage, %{})
    }

    {:ok, session} = Sessions.update_session(state.session, session_attrs)

    %{state | session: session, request_pid: nil, request_ref: nil}
  end

  defp broadcast(session_id, event, payload) do
    Phoenix.PubSub.broadcast(
      ClaudeConductor.PubSub,
      "session:#{session_id}",
      {event, payload}
    )
  end
end
