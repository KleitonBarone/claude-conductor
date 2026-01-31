defmodule ClaudeConductor.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add :status, :string, null: false, default: "idle"
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :exit_code, :integer
      add :task_id, references(:tasks, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:task_id])
    create index(:sessions, [:status])

    create table(:session_messages) do
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}
      add :session_id, references(:sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:session_messages, [:session_id])
  end
end
