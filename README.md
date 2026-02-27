# multirepo-space

Multi-repo workspace manager for AI coding agents. Scaffold, manage, and orchestrate workspaces that span multiple repositories — compatible with **Claude Code**, **Codex CLI**, **Gemini CLI**, **Copilot**, **Cursor**, and any tool supporting the [Agent Skills](https://agentskills.io) standard.

## What it does

- **Detects tech stacks** automatically (Angular, React, Spring Boot, Flutter, Go, Rust, .NET, Python, and more)
- **Generates workspace files**: `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, coordinator and specialist agents
- **Creates global transversal agents**: architecture, style, and code-review agents with read-only cross-repo access
- **YAML frontmatter** for Claude Code agents (name, model, description, tools) — `.agents/` stays plain markdown for Codex/Gemini
- **Agent Skills standard** — generates `.agents/skills/<name>/SKILL.md` for Warp, Codex, Cursor, Gemini CLI
- **Creates repo symlinks** for direct filesystem access
- **Persists configuration** (model assignments, global agent preferences) across `add`/`remove` operations
- **Cross-platform**: bash (macOS/Linux/WSL) + PowerShell (Windows)

## Install

```bash
npx skills add <owner>/multirepo-space -g
```

## Usage

```bash
# Scaffold a new workspace
multirepo-space setup ~/my-workspace ~/repos/frontend ~/repos/backend ~/repos/shared

# With custom model assignments
multirepo-space setup ~/my-workspace ~/repos/fe ~/repos/be --model-coordinator=sonnet

# Without global transversal agents
multirepo-space setup ~/my-workspace ~/repos/fe ~/repos/be --no-global-agents

# Add a repo to an existing workspace
multirepo-space add ~/my-workspace ~/repos/new-service

# Remove a repo
multirepo-space remove ~/my-workspace new-service

# Check workspace health
multirepo-space status ~/my-workspace
```

### Options

| Flag | Description |
|------|-------------|
| `-y`, `--yes` | Non-interactive mode (skip confirmations) |
| `-n`, `--dry-run` | Preview changes without writing |
| `-v`, `--verbose` | Detailed output |
| `-h`, `--help` | Show help |
| `--version` | Show version |
| `--model-coordinator=MODEL` | Model for coordinator agent (default: `opus`) |
| `--model-specialist=MODEL` | Model for specialist agents (default: `sonnet`) |
| `--model-global=MODEL` | Model for global agents (default: `sonnet`) |
| `--no-global-agents` | Do not generate global transversal agents |

## How it works

`multirepo-space setup` creates a central workspace directory with:

```
my-workspace/
├── AGENTS.md                    # Universal instructions (Codex, Copilot, Gemini, etc.)
├── CLAUDE.md                    # Claude Code instructions (same content)
├── .claude/
│   ├── settings.json            # additionalDirectories for Claude Code
│   ├── .multirepo-space.conf    # Persisted workspace configuration
│   └── agents/
│       ├── coordinator.md       # Orchestrator agent (with YAML frontmatter)
│       ├── repo-<alias>.md      # Specialist per repo (with YAML frontmatter)
│       ├── architecture-agent.md # Global: architecture & system design
│       ├── style-agent.md       # Global: visual consistency & UX
│       └── code-review-agent.md # Global: code quality & best practices
├── .agents/
│   ├── coordinator.md           # Orchestrator agent (plain markdown, Codex compatible)
│   ├── repo-<alias>.md          # Specialist per repo
│   ├── architecture-agent.md    # Global agents (plain markdown)
│   ├── style-agent.md
│   └── code-review-agent.md
├── repos/
│   ├── frontend -> /path/to/frontend
│   └── backend -> /path/to/backend
├── docs/
└── scripts/
```

### Agent hierarchy

```
Coordinator (opus)
├── architecture-agent (sonnet) — transversal, read-only
├── style-agent (sonnet) — transversal, read-only
├── code-review-agent (sonnet) — transversal, read-only
├── repo-frontend (sonnet) — can invoke global agents
└── repo-backend (sonnet) — can invoke global agents
```

### Multi-agent compatibility

- `.claude/agents/*.md` includes YAML frontmatter (`name`, `model`, `description`, `tools`) for Claude Code
- `.agents/*.md` contains plain markdown only (compatible with Codex, Gemini, Cursor)
- `.agents/skills/<name>/SKILL.md` follows the Agent Skills standard (`name`, `description`) for Warp, Codex, Cursor, Gemini CLI
- `AGENTS.md` is used as project rules by Warp, Codex, Gemini CLI, Cursor and 20+ tools


## Agent Skill

This project is also an [Agent Skill](https://agentskills.io). When installed, AI agents can invoke it automatically when you say things like "create a multi-repo workspace" or "add a repo to the workspace".

The SKILL.md is intentionally minimal — all heavy lifting is done by the bundled scripts, consuming zero tokens.

## Compatibility

| Tool | Reads | Generated files |
|------|-------|-----------------|
| Claude Code | `~/.claude/skills/` | `.claude/settings.json`, `CLAUDE.md`, `.claude/agents/` (with frontmatter) |
| Codex CLI | `~/.codex/skills/` | `AGENTS.md`, `.agents/` (plain markdown) |
| Gemini CLI | `~/.gemini/skills/` | `AGENTS.md`, `.agents/` (plain markdown) |
| Copilot | `.github/skills/` | `AGENTS.md` |
| Cursor | `~/.cursor/skills/` | `AGENTS.md` |

## License

MIT
