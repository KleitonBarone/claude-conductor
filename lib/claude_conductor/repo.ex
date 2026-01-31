defmodule ClaudeConductor.Repo do
  use Ecto.Repo,
    otp_app: :claude_conductor,
    adapter: Ecto.Adapters.SQLite3
end
