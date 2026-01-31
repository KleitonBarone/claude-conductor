# Claude Conductor

A task-focused UI for orchestrating multiple Claude Code sessions in parallel.

## What is this?

Claude Conductor is a web interface that wraps [Claude Code CLI](https://github.com/anthropics/claude-code) to provide:

- **Project Board** - Organize work into projects with multiple tasks
- **Parallel Sessions** - Run multiple Claude Code sessions simultaneously
- **Auto Context** - Automatically include and update project files as context
- **MCP Support** - Core MCP server integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Phoenix LiveView                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                      │
│  │Project A│  │Project B│  │Project C│   <- Board View      │
│  ├─────────┤  ├─────────┤  ├─────────┤                      │
│  │ Task 1  │  │ Task 1  │  │ Task 1  │   <- Task Cards      │
│  │ Task 2  │  │ Task 2  │  └─────────┘                      │
│  └─────────┘  └─────────┘                                   │
└─────────────────────────────────────────────────────────────┘
           │              │
           ▼              ▼
┌─────────────────────────────────────────────────────────────┐
│              DynamicSupervisor                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ SessionServer│  │ SessionServer│  │ SessionServer│       │
│  │  (GenServer) │  │  (GenServer) │  │  (GenServer) │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │               │
│         ▼                 ▼                 ▼               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │    Port      │  │    Port      │  │    Port      │       │
│  │ claude-code  │  │ claude-code  │  │ claude-code  │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                    SQLite (Ecto)                             │
│  projects │ tasks │ sessions │ context_files                │
└─────────────────────────────────────────────────────────────┘
```

## Tech Stack

- **Elixir 1.19** / **Erlang 28**
- **Phoenix 1.8** with LiveView
- **SQLite** via Ecto
- **Tailwind CSS**

## Prerequisites

- [mise](https://mise.jdx.dev/) for runtime management
- [Claude Code CLI](https://github.com/anthropics/claude-code) installed and configured

## Setup

```bash
# Clone the repo
git clone https://github.com/KleitonBarone/claude-conductor.git
cd claude-conductor

# Install runtimes and trust config
mise trust
mise install

# First-time setup (installs Hex, rebar, deps, creates DB)
mise run init

# Start the server
mise run s
```

Visit [localhost:4000](http://localhost:4000)

## Development

All commands are run via mise:

```bash
mise run s          # Start server
mise run t          # Run tests
mise run l          # Lint (format check + Credo)
mise run pc         # Pre-commit (compile, format, credo, test)
mise run m          # Run migrations
mise run c          # IEx console
```

### All Available Tasks

| Task | Alias | Description |
|------|-------|-------------|
| `server` | `s` | Start Phoenix server |
| `iex` | - | IEx with Phoenix server |
| `console` | `c` | IEx console (no server) |
| `test` | `t` | Run tests |
| `lint` | `l` | Format check + Credo |
| `format` | `f` | Format all code |
| `precommit` | `pc` | All checks before commit |
| `compile` | - | Compile with warnings as errors |
| `migrate` | `m` | Run migrations |
| `rollback` | - | Rollback last migration |
| `db:reset` | - | Drop, create, migrate |
| `db:seed` | - | Run seeds |
| `deps` | - | Get + compile deps |
| `deps:update` | - | Update all deps |
| `deps:outdated` | - | List outdated deps |
| `gen:migration` | - | Generate migration |
| `gen:context` | - | Generate context |
| `gen:live` | - | Generate LiveView |

### Code Quality

Before committing, run:

```bash
mise run pc
```

This runs:
1. `mix compile --warnings-as-errors`
2. `mix deps.unlock --unused`
3. `mix format`
4. `mix credo --strict`
5. `mix test`

## Project Status

**Work in Progress** - Core infrastructure is set up, features being built.

## License

MIT
