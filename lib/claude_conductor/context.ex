defmodule ClaudeConductor.Context do
  @moduledoc """
  The Context module manages project context files that are included
  in Claude Code sessions.
  """

  import Ecto.Query
  alias ClaudeConductor.Repo
  alias ClaudeConductor.Context.ContextFile

  def list_context_files(project_id) do
    ContextFile
    |> where(project_id: ^project_id)
    |> order_by(:path)
    |> Repo.all()
  end

  def list_included_files(project_id) do
    ContextFile
    |> where(project_id: ^project_id, included: true)
    |> order_by(:path)
    |> Repo.all()
  end

  def get_context_file!(id) do
    Repo.get!(ContextFile, id)
  end

  def get_context_file_by_path(project_id, path) do
    ContextFile
    |> where(project_id: ^project_id, path: ^path)
    |> Repo.one()
  end

  def create_context_file(attrs \\ %{}) do
    %ContextFile{}
    |> ContextFile.changeset(attrs)
    |> Repo.insert()
  end

  def update_context_file(%ContextFile{} = context_file, attrs) do
    context_file
    |> ContextFile.changeset(attrs)
    |> Repo.update()
  end

  def delete_context_file(%ContextFile{} = context_file) do
    Repo.delete(context_file)
  end

  def toggle_included(%ContextFile{} = context_file) do
    update_context_file(context_file, %{included: !context_file.included})
  end

  def upsert_context_file(project_id, path, attrs \\ %{}) do
    case get_context_file_by_path(project_id, path) do
      nil ->
        create_context_file(Map.merge(attrs, %{project_id: project_id, path: path}))

      context_file ->
        update_context_file(context_file, attrs)
    end
  end

  def sync_project_files(project_id, file_paths) do
    existing =
      project_id
      |> list_context_files()
      |> Map.new(&{&1.path, &1})

    # Add new files
    new_paths = file_paths -- Map.keys(existing)

    Enum.each(new_paths, fn path ->
      create_context_file(%{project_id: project_id, path: path})
    end)

    # Remove deleted files
    deleted_paths = Map.keys(existing) -- file_paths

    Enum.each(deleted_paths, fn path ->
      delete_context_file(existing[path])
    end)

    :ok
  end
end
