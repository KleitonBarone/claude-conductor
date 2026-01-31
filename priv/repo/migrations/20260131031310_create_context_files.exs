defmodule ClaudeConductor.Repo.Migrations.CreateContextFiles do
  use Ecto.Migration

  def change do
    create table(:context_files) do
      add :path, :string, null: false
      add :included, :boolean, null: false, default: true
      add :file_type, :string
      add :last_modified, :utc_datetime
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:context_files, [:project_id])
    create unique_index(:context_files, [:project_id, :path])
  end
end
