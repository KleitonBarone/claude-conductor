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

    %{project: project, task: task, session: session}
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
    test "session events are broadcast", %{session: session} do
      Phoenix.PubSub.subscribe(ClaudeConductor.PubSub, "session:#{session.id}")

      {:ok, _pid} = start_session_with_mock_provider(session.id)

      assert_receive {:session_started, %{}}, 5000
      assert_receive {:message, %{role: "assistant", content: "Hello from mock!"}}, 5000
      assert_receive {:session_completed, %{exit_code: 0}}, 10_000
    end
  end

  describe "database persistence" do
    test "session status and metadata are updated", %{session: session} do
      assert session.status == "idle"

      {:ok, _pid} = start_session_with_mock_provider(session.id)

      Process.sleep(200)

      updated_session = Sessions.get_session!(session.id)
      assert updated_session.status in ["running", "completed", "failed"]
      assert updated_session.started_at != nil

      wait_for_session_completion(session.id)

      final_session = Sessions.get_session!(session.id)
      assert final_session.status in ["completed", "failed"]
      assert final_session.finished_at != nil
      assert final_session.provider == "mock"
      assert final_session.model == "mock-model"
      assert final_session.request_id == "mock-request-123"
      assert final_session.usage["total_tokens"] == 7

      messages = Sessions.list_messages(session.id)
      assert Enum.any?(messages, &(&1.role == "assistant" and &1.content == "Hello from mock!"))
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────

  defp start_session_with_mock_provider(session_id) do
    SessionSupervisor.start_session(session_id,
      provider_module: ClaudeConductor.Sessions.MockProvider
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
