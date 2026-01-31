defmodule ClaudeConductor.Projects do
  @moduledoc """
  The Projects context manages projects and their tasks.
  """

  import Ecto.Query
  alias ClaudeConductor.Repo
  alias ClaudeConductor.Projects.{Project, Task}

  # ─────────────────────────────────────────────────────────────
  # Projects
  # ─────────────────────────────────────────────────────────────

  def list_projects do
    Project
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  def get_project!(id) do
    Repo.get!(Project, id)
  end

  def get_project_with_tasks!(id) do
    Project
    |> Repo.get!(id)
    |> Repo.preload(tasks: from(t in Task, order_by: t.position))
  end

  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  # ─────────────────────────────────────────────────────────────
  # Tasks
  # ─────────────────────────────────────────────────────────────

  def list_tasks(project_id) do
    Task
    |> where(project_id: ^project_id)
    |> order_by(:position)
    |> Repo.all()
  end

  def list_tasks_by_status(project_id, status) do
    Task
    |> where(project_id: ^project_id, status: ^status)
    |> order_by(:position)
    |> Repo.all()
  end

  def get_task!(id) do
    Repo.get!(Task, id)
  end

  def get_task_with_sessions!(id) do
    Task
    |> Repo.get!(id)
    |> Repo.preload(:sessions)
  end

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  def update_task_status(%Task{} = task, status) do
    update_task(task, %{status: status})
  end

  def reorder_tasks(project_id, task_ids) do
    Repo.transaction(fn ->
      task_ids
      |> Enum.with_index()
      |> Enum.each(fn {task_id, index} ->
        Task
        |> where(id: ^task_id, project_id: ^project_id)
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end
end
