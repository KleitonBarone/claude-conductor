defmodule ClaudeConductor.Sessions.SessionServer do
  @moduledoc """
  GenServer that manages a Claude Code CLI session via Port.

  ## Responsibilities

  - Opens Port to claude CLI with stream-json output
  - Parses streaming NDJSON and persists messages to database
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
  alias ClaudeConductor.Sessions.{JsonParser, SessionRegistry}
  alias ClaudeConductor.Projects

  @cli_executable "claude"
  @default_tools ~w(Bash Read Edit Write Glob Grep)

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
    cli_override = Keyword.get(opts, :cli_override)
    cli_args_override = Keyword.get(opts, :cli_args_override)
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
      port: nil,
      buffer: "",
      claude_session_id: nil,
      status: :starting,
      cli_override: cli_override,
      cli_args_override: cli_args_override
    }

    # Start the CLI process asynchronously
    {:ok, state, {:continue, :start_cli}}
  end

  @impl true
  def handle_continue(:start_cli, state) do
    case start_cli_port(state) do
      {:ok, port} ->
        # Update session status in database
        {:ok, session} = Sessions.start_session(state.session)
        broadcast(state.session_id, :session_started, %{})

        Logger.info("SessionServer started for session #{state.session_id}")
        {:noreply, %{state | port: port, session: session, status: :running}}

      {:error, reason} ->
        Logger.error("Failed to start CLI for session #{state.session_id}: #{inspect(reason)}")
        {:ok, _session} = Sessions.complete_session(state.session, 1)
        broadcast(state.session_id, :session_failed, %{reason: reason})
        {:stop, {:shutdown, reason}, state}
    end
  end

  @impl true
  def handle_continue(:graceful_stop, %{port: port} = state) when not is_nil(port) do
    # Close the port which sends SIGTERM to the CLI process
    # Keep the port reference so we can match the EXIT message
    Port.close(port)
    {:noreply, %{state | status: :stopping}}
  end

  def handle_continue(:graceful_stop, state) do
    # No port to close, complete the session and stop
    complete_and_stop(state, 0, :normal)
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:reply, :ok, %{state | status: :stopping}, {:continue, :graceful_stop}}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {new_buffer, events} = JsonParser.process_chunk(data, state.buffer)

    new_state =
      Enum.reduce(events, %{state | buffer: new_buffer}, fn event, acc ->
        handle_cli_event(event, acc)
      end)

    {:noreply, new_state}
  end

  def handle_info({port, {:exit_status, exit_code}}, %{port: port} = state) do
    Logger.info("CLI exited with code #{exit_code} for session #{state.session_id}")
    complete_and_stop(state, exit_code, :normal)
  end

  # Handle EXIT when we initiated the stop (status is :stopping)
  def handle_info({:EXIT, port, reason}, %{port: port, status: :stopping} = state) do
    Logger.info("Port closed gracefully for session #{state.session_id}: #{inspect(reason)}")
    complete_and_stop(state, 0, :normal)
  end

  # Handle unexpected EXIT (crash or external termination)
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("Port exited unexpectedly for session #{state.session_id}: #{inspect(reason)}")

    {:ok, session} = Sessions.complete_session(state.session, 1)
    broadcast(state.session_id, :session_failed, %{reason: :port_crashed})

    {:stop, :normal, %{state | port: nil, session: session}}
  end

  def handle_info(msg, state) do
    Logger.debug("SessionServer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SessionServer terminating for session #{state.session_id}: #{inspect(reason)}")

    # Close port if still open
    if state.port do
      Port.close(state.port)
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

    {:stop, stop_reason, %{state | port: nil, session: session}}
  end

  defp update_task_status(task, exit_code) do
    new_status = if exit_code == 0, do: "completed", else: "failed"
    Projects.update_task_status(task, new_status)
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions - Port Management
  # ─────────────────────────────────────────────────────────────

  defp start_cli_port(state) do
    cli_path = find_cli_executable(state)

    if is_nil(cli_path) do
      {:error, :cli_not_found}
    else
      args = build_cli_args(state)

      port_opts = [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args}
      ]

      # Add working directory if project path exists
      port_opts =
        if File.dir?(state.project.path) do
          [{:cd, String.to_charlist(state.project.path)} | port_opts]
        else
          Logger.warning("Project path does not exist: #{state.project.path}")
          port_opts
        end

      port = Port.open({:spawn_executable, cli_path}, port_opts)
      {:ok, port}
    end
  end

  defp find_cli_executable(state) do
    # Check for test override first
    case Map.get(state, :cli_override) do
      nil ->
        # Try common locations
        System.find_executable(@cli_executable) ||
          System.find_executable("claude.cmd") ||
          System.find_executable("claude.exe")

      override ->
        override
    end
  end

  defp build_cli_args(state) do
    # Use override args for testing if provided
    case Map.get(state, :cli_args_override) do
      nil ->
        base_args = [
          "-p",
          state.task.prompt || "Hello",
          "--output-format",
          "stream-json",
          "--allowedTools",
          Enum.join(@default_tools, ",")
        ]

        # Add --resume if we have a previous Claude session ID
        if state.claude_session_id do
          base_args ++ ["--resume", state.claude_session_id]
        else
          base_args
        end

      override_args ->
        override_args
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions - Event Handling
  # ─────────────────────────────────────────────────────────────

  defp handle_cli_event(%{"type" => "assistant"} = event, state) do
    content = extract_message_content(event)

    if content != "" do
      {:ok, _message} =
        Sessions.add_assistant_message(
          state.session_id,
          content,
          Map.take(event, ["id", "model", "stop_reason"])
        )
    end

    broadcast(state.session_id, :message, %{role: "assistant", content: content, event: event})
    state
  end

  defp handle_cli_event(%{"type" => "user"} = event, state) do
    content = extract_message_content(event)

    if content != "" do
      {:ok, _message} = Sessions.add_user_message(state.session_id, content, %{})
    end

    broadcast(state.session_id, :message, %{role: "user", content: content, event: event})
    state
  end

  defp handle_cli_event(%{"type" => "tool_use"} = event, state) do
    tool_name = Map.get(event, "name", "unknown")

    {:ok, _message} =
      Sessions.add_tool_message(
        state.session_id,
        "Tool: #{tool_name}",
        event
      )

    broadcast(state.session_id, :tool_use, event)
    state
  end

  defp handle_cli_event(%{"type" => "tool_result"} = event, state) do
    broadcast(state.session_id, :tool_result, event)
    state
  end

  defp handle_cli_event(%{"type" => "system"} = event, state) do
    # Capture the CLI session ID for potential --resume later
    claude_session_id = Map.get(event, "session_id")

    if claude_session_id do
      %{state | claude_session_id: claude_session_id}
    else
      state
    end
  end

  defp handle_cli_event(%{"type" => "content_block_delta"} = event, state) do
    # Partial/streaming content - broadcast but don't persist
    broadcast(state.session_id, :content_delta, event)
    state
  end

  defp handle_cli_event(%{"type" => "content_block_start"} = event, state) do
    broadcast(state.session_id, :content_block_start, event)
    state
  end

  defp handle_cli_event(%{"type" => "content_block_stop"} = event, state) do
    broadcast(state.session_id, :content_block_stop, event)
    state
  end

  defp handle_cli_event(%{"type" => "message_start"} = event, state) do
    broadcast(state.session_id, :message_start, event)
    state
  end

  defp handle_cli_event(%{"type" => "message_stop"} = event, state) do
    broadcast(state.session_id, :message_stop, event)
    state
  end

  defp handle_cli_event(%{"type" => type} = event, state) do
    Logger.debug("Unhandled CLI event type: #{type}")
    broadcast(state.session_id, :unknown_event, event)
    state
  end

  defp handle_cli_event(event, state) do
    Logger.debug("CLI event without type: #{inspect(event)}")
    state
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions - Helpers
  # ─────────────────────────────────────────────────────────────

  defp extract_message_content(%{"content" => content}) when is_binary(content) do
    content
  end

  defp extract_message_content(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&extract_content_block/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_message_content(%{"message" => %{"content" => content}}) do
    extract_message_content(%{"content" => content})
  end

  defp extract_message_content(_), do: ""

  defp extract_content_block(%{"type" => "text", "text" => text}), do: text
  defp extract_content_block(%{"type" => "tool_use"}), do: ""
  defp extract_content_block(_), do: ""

  defp broadcast(session_id, event, payload) do
    Phoenix.PubSub.broadcast(
      ClaudeConductor.PubSub,
      "session:#{session_id}",
      {event, payload}
    )
  end
end
