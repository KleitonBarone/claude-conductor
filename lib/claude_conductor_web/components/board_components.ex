defmodule ClaudeConductorWeb.BoardComponents do
  @moduledoc """
  Shared UI components for the project board.
  """
  use Phoenix.Component

  import ClaudeConductorWeb.CoreComponents

  @status_colors %{
    "pending" => "badge-neutral",
    "running" => "badge-info",
    "completed" => "badge-success",
    "failed" => "badge-error",
    "cancelled" => "badge-warning"
  }

  @doc """
  Renders a status badge for tasks.
  """
  attr :status, :string, required: true

  def status_badge(assigns) do
    color = Map.get(@status_colors, assigns.status, "badge-neutral")
    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={["badge badge-sm", @color]}>{@status}</span>
    """
  end

  @doc """
  Renders a Kanban column with title, count, and content.
  """
  attr :title, :string, required: true
  attr :status, :string, required: true
  attr :count, :integer, default: 0
  slot :inner_block, required: true

  def kanban_column(assigns) do
    ~H"""
    <div class="flex-1 min-w-[280px] max-w-[350px]">
      <div class="flex items-center gap-2 mb-3">
        <h3 class="font-semibold text-base-content">{@title}</h3>
        <span class="badge badge-sm badge-ghost">{@count}</span>
      </div>

      <div class="space-y-3 min-h-[200px] bg-base-200/50 rounded-lg p-3">
        {render_slot(@inner_block)}
        <div :if={@count == 0} class="text-center text-base-content/50 py-8 text-sm">No tasks</div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a project card for the project list.
  """
  attr :project, :map, required: true
  attr :navigate, :string, required: true

  def project_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer"
    >
      <div class="card-body">
        <h2 class="card-title text-lg">{@project.name}</h2>

        <p class="text-sm text-base-content/70 font-mono truncate">{@project.path}</p>

        <p :if={@project.description} class="text-sm text-base-content/60 line-clamp-2">
          {@project.description}
        </p>

        <div class="card-actions justify-end mt-2">
          <span class="badge badge-ghost">{@project.task_count || 0} tasks</span>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders an empty state message.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <.icon name="hero-inbox" class="mx-auto size-12 text-base-content/30" />
      <h3 class="mt-4 text-lg font-semibold text-base-content">{@title}</h3>

      <p :if={@description} class="mt-2 text-base-content/60">{@description}</p>

      <div :if={@action != []} class="mt-6">{render_slot(@action)}</div>
    </div>
    """
  end
end
