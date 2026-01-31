# Claude Conductor - Agent Guidelines

This is Claude Conductor, a Phoenix LiveView application for orchestrating multiple Claude Code CLI sessions.

## Project Overview

Claude Conductor wraps the Claude Code CLI to provide:
- A board-style UI for managing projects and tasks
- Parallel Claude Code session execution
- Automatic context management from project files
- Real-time streaming of session output via LiveView

## Architecture

```
ClaudeConductor (Application)
├── ClaudeConductor.Repo              # SQLite database
├── ClaudeConductor.Projects          # Context for projects/tasks
├── ClaudeConductor.Sessions          # Context for Claude Code sessions
│   ├── SessionSupervisor             # DynamicSupervisor for sessions
│   └── SessionServer                 # GenServer wrapping Claude Code CLI
└── ClaudeConductorWeb                # Phoenix web layer
    ├── BoardLive                     # Main board view
    ├── ProjectLive                   # Project detail view
    └── SessionLive                   # Session detail view
```

## Project-Specific Guidelines

### Development Workflow

- Use `mise run <task>` for all commands (see README for full list)
- Run `mise run pc` (precommit) before committing
- Use `mise run gen:migration name` for new migrations
- Use `mise run gen:live` for new LiveViews

### GenServer Patterns (SessionServer)

When working with `ClaudeConductor.Sessions.SessionServer`:

```elixir
# Starting a session - always use DynamicSupervisor
DynamicSupervisor.start_child(
  ClaudeConductor.Sessions.SessionSupervisor,
  {SessionServer, task: task, project: project}
)

# Sessions are identified by task_id
SessionServer.send_message(task_id, "your prompt here")
SessionServer.stop(task_id)
```

### Port Communication (Claude Code CLI)

When working with the Claude Code CLI wrapper:

```elixir
# Ports use binary mode for proper output handling
port = Port.open({:spawn_executable, cli_path}, [
  :binary,
  :exit_status,
  :use_stdio,
  args: ["--print", "--output-format", "json"]
])

# Always handle port messages in handle_info
def handle_info({port, {:data, data}}, state) when port == state.port do
  # Process CLI output
end

def handle_info({port, {:exit_status, status}}, state) do
  # Handle CLI exit
end
```

### PubSub for Real-time Updates

Session output streams to LiveView via PubSub:

```elixir
# In SessionServer - broadcast output
Phoenix.PubSub.broadcast(
  ClaudeConductor.PubSub,
  "session:#{task_id}",
  {:session_output, output}
)

# In LiveView - subscribe and handle
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(ClaudeConductor.PubSub, "session:#{task_id}")
  {:ok, socket}
end

def handle_info({:session_output, output}, socket) do
  {:noreply, stream_insert(socket, :outputs, output)}
end
```

### Database Schema

Key models:
- `Project` - has many tasks, stores path to codebase
- `Task` - belongs to project, has many sessions
- `Session` - belongs to task, stores conversation history
- `ContextFile` - belongs to project, tracks included files

### File Organization

```
lib/
├── claude_conductor/
│   ├── projects/           # Projects context
│   │   ├── project.ex      # Project schema
│   │   └── task.ex         # Task schema
│   ├── sessions/           # Sessions context
│   │   ├── session.ex      # Session schema
│   │   ├── session_server.ex
│   │   └── session_supervisor.ex
│   └── context/            # Context management
│       └── context_file.ex
└── claude_conductor_web/
    └── live/
        ├── board_live.ex
        ├── project_live.ex
        └── session_live.ex
```

## Code Style

- Use `mise run format` to format code
- Use `mise run credo` for static analysis
- Follow the naming: `ClaudeConductor.*` for business logic, `ClaudeConductorWeb.*` for web

---

<!-- Phoenix/Elixir guidelines below - keep for reference -->

## Phoenix v1.8 Guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `ClaudeConductorWeb.Layouts` module is aliased in the `claude_conductor_web.ex` file
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. **Never** call `<.flash_group>` outside of `layouts.ex`
- **Always** use the `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for icons
- **Always** use the `<.input>` component for form inputs from `core_components.ex`

### JS and CSS Guidelines

- **Use Tailwind CSS classes** for styling
- Tailwind v4 uses the new import syntax in `app.css` - maintain it
- **Never** use `@apply` in CSS
- **Never** write inline `<script>` tags in templates

## Elixir Guidelines

- Lists **do not support index access** - use `Enum.at/2` or pattern matching
- Variables are immutable but rebindable - **always** bind block expression results:

  ```elixir
  # VALID
  socket =
    if connected?(socket) do
      assign(socket, :val, val)
    else
      socket
    end
  ```

- **Never** nest multiple modules in the same file
- **Never** use `String.to_atom/1` on user input
- Predicate functions end with `?` (e.g., `valid?/1`), not `is_valid/1`
- Use `start_supervised!/1` in tests for process cleanup

## Ecto Guidelines

- **Always** preload associations when they'll be accessed in templates
- Use `:string` type for text fields in schemas
- Use `Ecto.Changeset.get_field/2` to access changeset fields
- **Always** use `mix ecto.gen.migration` to generate migrations

## LiveView Guidelines

- Use `<.link navigate={path}>` and `<.link patch={path}>`, not deprecated functions
- **Avoid LiveComponents** unless truly necessary
- Name LiveViews with `Live` suffix: `BoardLive`, `ProjectLive`
- **Always** use streams for collections to avoid memory issues
- Use `phx-update="stream"` on parent elements with streams
- For empty states with streams, use `hidden only:block` pattern

### LiveView Streams

```elixir
# Append
stream(socket, :items, [new_item])

# Reset (for filtering)
stream(socket, :items, filtered_items, reset: true)

# Delete
stream_delete(socket, :items, item)
```

Template:
```heex
<div id="items" phx-update="stream">
  <div class="hidden only:block">No items yet</div>
  <div :for={{id, item} <- @streams.items} id={id}>
    {item.name}
  </div>
</div>
```

### Forms

**Always** use `to_form/2` and `<.input>`:

```elixir
# In LiveView
socket = assign(socket, form: to_form(changeset))
```

```heex
<.form for={@form} id="task-form" phx-submit="save">
  <.input field={@form[:name]} type="text" />
</.form>
```

**Never** pass changesets directly to templates.

## Test Guidelines

- Use `start_supervised!/1` for processes
- Use `Process.monitor/1` instead of `Process.sleep/1`
- Use `Phoenix.LiveViewTest` and `LazyHTML` for LiveView tests
- Test element presence, not raw HTML content
