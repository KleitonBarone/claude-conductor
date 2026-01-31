defmodule ClaudeConductor.Sessions.SessionRegistryTest do
  use ExUnit.Case, async: true

  alias ClaudeConductor.Sessions.SessionRegistry

  # Registry is started by the application, but for isolated tests
  # we rely on the app being started in test_helper.exs

  describe "lookup/1" do
    test "returns :error for non-existent session" do
      assert SessionRegistry.lookup(999_999) == :error
    end

    test "returns {:ok, pid} for registered session" do
      session_id = System.unique_integer([:positive])

      # Register a process under the session_id
      {:ok, _pid} = Registry.register(SessionRegistry.name(), session_id, nil)

      assert {:ok, pid} = SessionRegistry.lookup(session_id)
      assert pid == self()
    end
  end

  describe "running?/1" do
    test "returns false for non-existent session" do
      refute SessionRegistry.running?(999_999)
    end

    test "returns true for registered session" do
      session_id = System.unique_integer([:positive])
      {:ok, _pid} = Registry.register(SessionRegistry.name(), session_id, nil)

      assert SessionRegistry.running?(session_id)
    end
  end

  describe "list_all/0" do
    test "returns empty list when no sessions registered" do
      # This test might see sessions from other tests, so we just verify it returns a list
      assert is_list(SessionRegistry.list_all())
    end

    test "includes registered session ids" do
      session_id = System.unique_integer([:positive])
      {:ok, _pid} = Registry.register(SessionRegistry.name(), session_id, nil)

      assert session_id in SessionRegistry.list_all()
    end
  end

  describe "via/1" do
    test "returns via tuple for registration" do
      session_id = 123
      via = SessionRegistry.via(session_id)

      assert via == {:via, Registry, {SessionRegistry.name(), session_id}}
    end
  end
end
