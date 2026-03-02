defmodule ClaudeConductor.Repo.Migrations.AddLlmMetadataToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :provider, :string
      add :model, :string
      add :request_id, :string
      add :usage, :map, default: %{}
    end

    create index(:sessions, [:request_id])
  end
end
