defmodule ClaudeConductor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ClaudeConductorWeb.Telemetry,
      ClaudeConductor.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:claude_conductor, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:claude_conductor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ClaudeConductor.PubSub},
      # Session management for Claude Code CLI
      ClaudeConductor.Sessions.SessionRegistry,
      ClaudeConductor.Sessions.SessionSupervisor,
      # Start to serve requests, typically the last entry
      ClaudeConductorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ClaudeConductor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ClaudeConductorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
