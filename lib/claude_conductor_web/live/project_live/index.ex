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
      |> assign(:show_form, false)
      |> assign(:form, to_form(Projects.change_project(%Project{})))
      |> stream(:projects, projects)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Projects")}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, :show_form, !socket.assigns.show_form)}
  end

  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    case Projects.create_project(params) do
      {:ok, project} ->
        socket =
          socket
          |> assign(:has_projects, true)
          |> assign(:show_form, false)
          |> assign(:form, to_form(Projects.change_project(%Project{})))
          |> stream_insert(:projects, Map.put(project, :task_count, 0), at: 0)
          |> put_flash(:info, "Project created")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    {:ok, _} = Projects.delete_project(project)

    {:noreply, stream_delete(socket, :projects, project)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="p-4 md:p-6 lg:p-8 max-w-7xl mx-auto">
        <%!-- Header with inline form toggle --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
          <h1 class="text-2xl font-bold">Projects</h1>
          <button
            phx-click="toggle_form"
            class={["btn", (@show_form && "btn-ghost") || "btn-primary"]}
          >
            <.icon name={(@show_form && "hero-x-mark") || "hero-plus"} class="size-5" />
            <span class="hidden sm:inline">{(@show_form && "Cancel") || "New Project"}</span>
          </button>
        </div>

        <%!-- Inline create form --%>
        <div
          :if={@show_form}
          class="card bg-base-200 mb-6 animate-in slide-in-from-top-2 duration-200"
        >
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Project Name"
                  placeholder="My Project"
                  phx-debounce="300"
                />
                <.input
                  field={@form[:path]}
                  type="text"
                  label="Project Path"
                  placeholder="C:/path/to/project"
                  phx-debounce="300"
                />
              </div>
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description (optional)"
                placeholder="What is this project about?"
                rows="2"
                phx-debounce="300"
              />
              <div class="flex justify-end">
                <.button class="btn-primary">
                  <.icon name="hero-check" class="size-4" /> Create Project
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Projects grid --%>
        <div
          :if={@has_projects}
          id="projects"
          phx-update="stream"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4"
        >
          <div
            :for={{id, project} <- @streams.projects}
            id={id}
            class="card bg-base-100 shadow-sm hover:shadow-md transition-all hover:-translate-y-0.5 h-full relative group"
          >
            <.link navigate={~p"/projects/#{project}"} class="card-body p-4">
              <h2 class="card-title text-base">{project.name}</h2>
              <p class="text-xs text-base-content/60 font-mono truncate">{project.path}</p>
              <p
                :if={project.description}
                class="text-sm text-base-content/70 line-clamp-2 mt-1"
              >
                {project.description}
              </p>
              <div class="flex items-center justify-between mt-auto pt-2">
                <span class="badge badge-ghost badge-sm">
                  {project.task_count || 0} tasks
                </span>
                <.icon name="hero-chevron-right" class="size-4 text-base-content/40" />
              </div>
            </.link>
            <button
              class="btn btn-ghost btn-xs btn-circle absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity text-error"
              phx-click="delete"
              phx-value-id={project.id}
              data-confirm="Delete this project and all its tasks?"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
        </div>

        <%!-- Empty state --%>
        <.empty_state
          :if={!@has_projects && !@show_form}
          title="No projects yet"
          description="Create your first project to start orchestrating Claude Code tasks."
        >
          <:action>
            <button phx-click="toggle_form" class="btn btn-primary">
              <.icon name="hero-plus" class="size-5" /> Create Project
            </button>
          </:action>
        </.empty_state>
      </div>
    </Layouts.app>
    """
  end
end
