defmodule ClaudeConductorWeb.ProjectLive.Show do
  @moduledoc """
  LiveView for the project board - Kanban-style task management.
  """
  use ClaudeConductorWeb, :live_view

  alias ClaudeConductor.Projects
  alias ClaudeConductor.Projects.Task
  alias ClaudeConductor.Sessions

  import ClaudeConductorWeb.BoardComponents

  @statuses ["pending", "running", "completed", "failed"]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project_with_tasks!(id)

    if connected?(socket) do
      subscribe_to_running_sessions(project.tasks)
    end

    socket =
      socket
      |> assign(:project, project)
      |> assign(:tasks_by_status, group_tasks_by_status(project.tasks))
      |> assign(:selected_task, nil)
      |> assign(:selected_session, nil)
      |> assign(:streaming_content, [])
      |> assign(:messages, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:page_title, socket.assigns.project.name)
    |> assign(:task, nil)
  end

  defp apply_action(socket, :new_task, _params) do
    socket
    |> assign(:page_title, "New Task")
    |> assign(:task, %Task{project_id: socket.assigns.project.id})
  end

  # ─────────────────────────────────────────────────────────────
  # Event Handlers
  # ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_task", %{"id" => id}, socket) do
    task = Projects.get_task!(id)
    session = Sessions.get_latest_session(task.id)
    messages = if session, do: Sessions.list_messages(session.id), else: []

    # Subscribe to session if running
    if session && session.status == "running" do
      Phoenix.PubSub.subscribe(ClaudeConductor.PubSub, "session:#{session.id}")
    end

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:selected_session, session)
      |> assign(:messages, messages)
      |> assign(:streaming_content, [])

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_task, nil)
     |> assign(:selected_session, nil)
     |> assign(:messages, [])
     |> assign(:streaming_content, [])}
  end

  def handle_event("run_task", %{"id" => id}, socket) do
    task = Projects.get_task!(id)

    case Sessions.create_and_run_session(%{task_id: task.id}) do
      {:ok, session, _pid} ->
        # Subscribe to the new session
        Phoenix.PubSub.subscribe(ClaudeConductor.PubSub, "session:#{session.id}")

        # Update task status
        {:ok, updated_task} = Projects.update_task_status(task, "running")

        socket =
          socket
          |> refresh_tasks()
          |> assign(:selected_task, updated_task)
          |> assign(:selected_session, session)
          |> assign(:messages, [])
          |> assign(:streaming_content, [])
          |> put_flash(:info, "Session started")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start session: #{inspect(reason)}")}
    end
  end

  def handle_event("stop_session", %{"id" => id}, socket) do
    session_id = String.to_integer(id)

    case Sessions.stop_running_session(session_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Session stopping...")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({ClaudeConductorWeb.ProjectLive.TaskFormComponent, {:saved, _task}}, socket) do
    {:noreply, refresh_tasks(socket)}
  end

  # ─────────────────────────────────────────────────────────────
  # PubSub Handlers
  # ─────────────────────────────────────────────────────────────

  def handle_info({:session_started, _payload}, socket) do
    {:noreply, refresh_tasks(socket)}
  end

  def handle_info({:session_completed, %{exit_code: exit_code}}, socket) do
    # Update task status based on exit code
    if socket.assigns.selected_task do
      new_status = if exit_code == 0, do: "completed", else: "failed"
      Projects.update_task_status(socket.assigns.selected_task, new_status)
    end

    # Reload messages from database
    messages =
      if socket.assigns.selected_session do
        Sessions.list_messages(socket.assigns.selected_session.id)
      else
        []
      end

    socket =
      socket
      |> refresh_tasks()
      |> assign(:messages, messages)
      |> assign(:streaming_content, [])
      |> put_flash(:info, "Session completed (exit code: #{exit_code})")

    {:noreply, socket}
  end

  def handle_info({:session_failed, %{reason: reason}}, socket) do
    if socket.assigns.selected_task do
      Projects.update_task_status(socket.assigns.selected_task, "failed")
    end

    socket =
      socket
      |> refresh_tasks()
      |> put_flash(:error, "Session failed: #{inspect(reason)}")

    {:noreply, socket}
  end

  def handle_info({:message, %{role: role, content: content}}, socket) do
    # Add complete message to streaming content
    new_content = {System.unique_integer(), "#{role}: #{content}"}

    {:noreply,
     update(socket, :streaming_content, fn content_list ->
       content_list ++ [new_content]
     end)}
  end

  def handle_info({:content_delta, %{"delta" => %{"text" => text}}}, socket) do
    # Append delta to last streaming item or create new
    {:noreply,
     update(socket, :streaming_content, fn content_list ->
       case content_list do
         [] ->
           [{System.unique_integer(), text}]

         list ->
           {id, last_text} = List.last(list)
           List.replace_at(list, -1, {id, last_text <> text})
       end
     end)}
  end

  def handle_info({:tool_use, %{"name" => name}}, socket) do
    new_content = {System.unique_integer(), "[Tool: #{name}]"}

    {:noreply,
     update(socket, :streaming_content, fn content_list ->
       content_list ++ [new_content]
     end)}
  end

  def handle_info({:tool_result, _event}, socket) do
    {:noreply, socket}
  end

  def handle_info({event, _payload}, socket)
      when event in [
             :content_block_start,
             :content_block_stop,
             :message_start,
             :message_stop,
             :session_terminated,
             :unknown_event
           ] do
    {:noreply, socket}
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions
  # ─────────────────────────────────────────────────────────────

  defp subscribe_to_running_sessions(tasks) do
    tasks
    |> Enum.filter(&(&1.status == "running"))
    |> Enum.each(fn task ->
      if session = Sessions.get_running_session(task.id) do
        Phoenix.PubSub.subscribe(ClaudeConductor.PubSub, "session:#{session.id}")
      end
    end)
  end

  defp group_tasks_by_status(tasks) do
    grouped = Enum.group_by(tasks, & &1.status)

    @statuses
    |> Enum.map(fn status -> {status, Map.get(grouped, status, [])} end)
    |> Map.new()
  end

  defp refresh_tasks(socket) do
    project = Projects.get_project_with_tasks!(socket.assigns.project.id)

    socket
    |> assign(:project, project)
    |> assign(:tasks_by_status, group_tasks_by_status(project.tasks))
  end

  defp status_title("pending"), do: "Pending"
  defp status_title("running"), do: "Running"
  defp status_title("completed"), do: "Completed"
  defp status_title("failed"), do: "Failed"
  defp status_title(status), do: String.capitalize(status)

  # ─────────────────────────────────────────────────────────────
  # Render
  # ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :statuses, @statuses)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container mx-auto px-4 py-8">
        <%!-- Header --%>
        <div class="flex justify-between items-start mb-8">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
                <.icon name="hero-arrow-left" class="size-4" />
              </.link>
              <h1 class="text-2xl font-bold">{@project.name}</h1>
            </div>

            <p class="text-base-content/60 font-mono text-sm ml-10">{@project.path}</p>
          </div>

          <.link patch={~p"/projects/#{@project}/tasks/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-5" /> New Task
          </.link>
        </div>
        <%!-- Kanban Board --%>
        <div class="flex gap-4 overflow-x-auto pb-4">
          <.kanban_column
            :for={status <- @statuses}
            title={status_title(status)}
            status={status}
            count={length(Map.get(@tasks_by_status, status, []))}
          >
            <div
              :for={task <- Map.get(@tasks_by_status, status, [])}
              id={"task-#{task.id}"}
              class={[
                "card bg-base-100 shadow-sm cursor-pointer hover:shadow-md transition-shadow",
                @selected_task && @selected_task.id == task.id && "ring-2 ring-primary"
              ]}
              phx-click="select_task"
              phx-value-id={task.id}
            >
              <div class="card-body p-4">
                <h3 class="card-title text-sm">{task.title}</h3>

                <p :if={task.prompt} class="text-xs text-base-content/70 line-clamp-2">
                  {task.prompt}
                </p>

                <div class="card-actions justify-between items-center mt-2">
                  <.status_badge status={task.status} />
                  <button
                    :if={task.status in ["pending", "completed", "failed", "cancelled"]}
                    class="btn btn-primary btn-xs"
                    phx-click="run_task"
                    phx-value-id={task.id}
                  >
                    <.icon name="hero-play" class="size-3" /> Run
                  </button>
                  <span
                    :if={task.status == "running"}
                    class="loading loading-spinner loading-xs text-info"
                  >
                  </span>
                </div>
              </div>
            </div>
          </.kanban_column>
        </div>
        <%!-- Task Detail Drawer --%>
        <div
          :if={@selected_task}
          class="fixed inset-y-0 right-0 w-96 bg-base-200 shadow-xl z-40 overflow-hidden flex flex-col"
        >
          <div class="flex justify-between items-center p-4 border-b border-base-300">
            <h2 class="text-lg font-semibold truncate">{@selected_task.title}</h2>

            <button class="btn btn-ghost btn-sm" phx-click="close_detail">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-4 space-y-4">
            <%!-- Prompt --%>
            <div>
              <h4 class="font-medium text-sm mb-2">Prompt</h4>
              <pre class="whitespace-pre-wrap text-xs bg-base-300 rounded-lg p-3">{@selected_task.prompt || "(no prompt)"}</pre>
            </div>
            <%!-- Session Controls --%>
            <div class="flex gap-2">
              <button
                :if={@selected_task.status in ["pending", "completed", "failed", "cancelled"]}
                class="btn btn-primary btn-sm flex-1"
                phx-click="run_task"
                phx-value-id={@selected_task.id}
              >
                <.icon name="hero-play" class="size-4" /> Run Task
              </button>
              <button
                :if={@selected_task.status == "running" && @selected_session}
                class="btn btn-error btn-sm flex-1"
                phx-click="stop_session"
                phx-value-id={@selected_session.id}
              >
                <.icon name="hero-stop" class="size-4" /> Stop
              </button>
            </div>
            <%!-- Session Output --%>
            <div :if={@selected_session || @streaming_content != []}>
              <h4 class="font-medium text-sm mb-2">
                Session Output
                <span
                  :if={@selected_task.status == "running"}
                  class="loading loading-dots loading-xs ml-2"
                >
                </span>
              </h4>

              <div
                id="session-output"
                class="bg-base-300 rounded-lg p-3 h-80 overflow-y-auto font-mono text-xs space-y-1"
                phx-hook="ScrollBottom"
              >
                <%!-- Persisted messages --%>
                <div :for={message <- @messages} class={message_class(message.role)}>
                  <span class="font-bold">{message.role}:</span>
                  <span class="whitespace-pre-wrap">{message.content}</span>
                </div>
                <%!-- Streaming content --%>
                <div
                  :for={{id, content} <- @streaming_content}
                  id={"stream-#{id}"}
                  class="text-primary whitespace-pre-wrap"
                >
                  {content}
                </div>
                <%!-- Running indicator --%>
                <div
                  :if={
                    @selected_task.status == "running" && @streaming_content == [] && @messages == []
                  }
                  class="text-base-content/50"
                >
                  Waiting for output...
                </div>
              </div>
            </div>
          </div>
        </div>
        <%!-- Backdrop for drawer --%>
        <div
          :if={@selected_task}
          class="fixed inset-0 bg-black/20 z-30"
          phx-click="close_detail"
        >
        </div>
        <%!-- New Task Modal --%>
        <.modal
          :if={@live_action == :new_task}
          id="task-modal"
          show
          on_cancel={JS.patch(~p"/projects/#{@project}")}
        >
          <.live_component
            module={ClaudeConductorWeb.ProjectLive.TaskFormComponent}
            id={:new}
            title="New Task"
            action={:new}
            task={@task}
            project={@project}
            patch={~p"/projects/#{@project}"}
          />
        </.modal>
      </div>
    </Layouts.app>
    """
  end

  defp message_class("assistant"), do: "text-success"
  defp message_class("user"), do: "text-info"
  defp message_class("tool"), do: "text-warning"
  defp message_class(_), do: "text-base-content"
end
