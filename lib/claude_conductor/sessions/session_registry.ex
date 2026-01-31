defmodule ClaudeConductor.Sessions.SessionRegistry do
  @moduledoc """
  Registry for looking up SessionServer processes by session_id.

  Provides helper functions for process discovery and enumeration.
  """

  @registry_name __MODULE__

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry_name)
  end

  @doc """
  Returns the registry name for use in via tuples.
  """
  def name, do: @registry_name

  @doc """
  Look up a session's PID by session_id.

  Returns `{:ok, pid}` if found, `:error` if not running.
  """
  def lookup(session_id) do
    case Registry.lookup(@registry_name, session_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Check if a session is currently running.
  """
  def running?(session_id) do
    match?({:ok, _}, lookup(session_id))
  end

  @doc """
  List all running session IDs.
  """
  def list_all do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Returns a via tuple for registering/looking up a session.
  """
  def via(session_id) do
    {:via, Registry, {@registry_name, session_id}}
  end
end
