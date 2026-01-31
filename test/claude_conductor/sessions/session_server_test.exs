defmodule ClaudeConductor.Sessions.SessionServerTest do
  use ClaudeConductor.DataCase, async: false

  alias ClaudeConductor.Sessions
  alias ClaudeConductor.Sessions.{SessionServer, SessionSupervisor, SessionRegistry}
  alias ClaudeConductor.Projects

  @moduletag :capture_log

  setup do
    # Create test project and task
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        path: System.tmp_dir!()
      })

    {:ok, task} =
      Projects.create_task(%{
        title: "Test Task",
        prompt: "Say hello",
        project_id: project.id
      })

    {:ok, session} = Sessions.create_session(%{task_id: task.id})

    # Build path to mock CLI script
    mock_cli = build_mock_cli_command()

    %{project: project, task: task, session: session, mock_cli: mock_cli}
  end

  defp build_mock_cli_command do
    # Use elixir to run our mock script
    elixir_path = System.find_executable("elixir")
    mock_script = Path.join([File.cwd!(), "test", "support", "mock_claude_cli.exs"])

    if elixir_path && File.exists?(mock_script) do
      {elixir_path, mock_script}
    else
      nil
    end
  end

  describe "start_link/1" do
    test "returns error if session doesn't exist" do
      # start_link is called by the supervisor, so we test via supervisor
      # which will fail to start if session doesn't exist
      result = SessionSupervisor.start_session(999_999)
      assert {:error, _} = result
    end
  end

  describe "get_status/1" do
    test "returns :not_running for non-existent session" do
      assert SessionServer.get_status(999_999) == :not_running
    end
  end

  describe "stop/1" do
    test "returns error for non-existent session" do
      assert SessionServer.stop(999_999) == {:error, :not_running}
    end
  end

  describe "SessionSupervisor.start_session/2" do
    test "prevents duplicate sessions", %{session: session} do
      # Register a fake process to simulate running session
      {:ok, _} = Registry.register(SessionRegistry.name(), session.id, nil)

      result = SessionSupervisor.start_session(session.id)

      assert {:error, {:already_started, _pid}} = result
    end
  end

  describe "PubSub integration" do
    @tag :mock_cli
    test "session events are broadcast", %{session: session, mock_cli: mock_cli} do
      case mock_cli do
        nil ->
          :ok

        {elixir_path, mock_script} ->
          # Subscribe to session events
          Phoenix.PubSub.subscribe(ClaudeConductor.PubSub, "session:#{session.id}")

          # Start session with mock CLI
          {:ok, _pid} = start_session_with_mock(session.id, elixir_path, mock_script)

          # Should receive session_started event
          assert_receive {:session_started, %{}}, 5000

          # Wait for session to complete (exit code may be 0 or non-zero depending on mock)
          assert_receive {:session_completed, %{exit_code: _}}, 10_000
      end
    end
  end

  describe "database persistence" do
    @tag :mock_cli
    test "session status is updated on start", %{session: session, mock_cli: mock_cli} do
      case mock_cli do
        nil ->
          :ok

        {elixir_path, mock_script} ->
          # Initial status should be idle
          assert session.status == "idle"

          {:ok, _pid} = start_session_with_mock(session.id, elixir_path, mock_script)

          # Wait a bit for status update
          Process.sleep(200)

          # Check session is now running or completed
          updated_session = Sessions.get_session!(session.id)
          assert updated_session.status in ["running", "completed", "failed"]
          assert updated_session.started_at != nil

          # Wait for completion
          wait_for_session_completion(session.id)

          # Check session has finished
          final_session = Sessions.get_session!(session.id)
          assert final_session.status in ["completed", "failed"]
          assert final_session.finished_at != nil
      end
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────

  defp start_session_with_mock(session_id, elixir_path, mock_script) do
    # Create a wrapper that calls elixir with the mock script
    SessionSupervisor.start_session(session_id,
      cli_override: elixir_path,
      cli_args_override: [mock_script]
    )
  end

  defp wait_for_session_completion(session_id, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_until(
      fn ->
        !SessionRegistry.running?(session_id)
      end,
      deadline
    )
  end

  defp wait_until(fun, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      raise "Timeout waiting for condition"
    end

    if fun.() do
      :ok
    else
      Process.sleep(50)
      wait_until(fun, deadline)
    end
  end
end
