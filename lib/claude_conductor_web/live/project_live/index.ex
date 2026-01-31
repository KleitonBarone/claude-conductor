defmodule ClaudeConductorWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and creating projects.
  """
  use ClaudeConductorWeb, :live_view

  alias ClaudeConductor.Projects
  alias ClaudeConductor.Projects.Project

  import ClaudeConductorWeb.BoardComponents

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list_projects_with_task_count()

    socket =
      socket
      |> assign(:has_projects, projects != [])
      |> stream(:projects, projects)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Project")
    |> assign(:project, %Project{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Projects")
    |> assign(:project, nil)
  end

  @impl true
  def handle_info({ClaudeConductorWeb.ProjectLive.FormComponent, {:saved, project}}, socket) do
    socket =
      socket
      |> assign(:has_projects, true)
      |> stream_insert(:projects, Map.put(project, :task_count, 0), at: 0)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    {:ok, _} = Projects.delete_project(project)

    {:noreply, stream_delete(socket, :projects, project)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container mx-auto px-4 py-8">
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-2xl font-bold">Projects</h1>
            <p class="text-base-content/60">Manage your Claude Code projects</p>
          </div>
          <.link patch={~p"/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-5" /> New Project
          </.link>
        </div>

        <div
          :if={@has_projects}
          id="projects"
          phx-update="stream"
          class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
        >
          <div :for={{id, project} <- @streams.projects} id={id}>
            <.project_card project={project} navigate={~p"/projects/#{project}"} />
          </div>
        </div>

        <.empty_state
          :if={!@has_projects}
          title="No projects yet"
          description="Create your first project to get started."
        >
          <:action>
            <.link patch={~p"/new"} class="btn btn-primary">
              <.icon name="hero-plus" class="size-5" /> New Project
            </.link>
          </:action>
        </.empty_state>

        <.modal :if={@live_action == :new} id="project-modal" show on_cancel={JS.patch(~p"/")}>
          <.live_component
            module={ClaudeConductorWeb.ProjectLive.FormComponent}
            id={:new}
            title="New Project"
            action={@live_action}
            project={@project}
            patch={~p"/"}
          />
        </.modal>
      </div>
    </Layouts.app>
    """
  end
end
