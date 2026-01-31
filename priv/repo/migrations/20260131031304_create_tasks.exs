defmodule ClaudeConductor.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :string, null: false
      add :prompt, :text
      add :status, :string, null: false, default: "pending"
      add :position, :integer, null: false, default: 0
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:status])
  end
end
