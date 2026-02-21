# multirepo-space

Multi-repo workspace manager for AI coding agents. Scaffold, manage, and orchestrate workspaces that span multiple repositories — compatible with **Claude Code**, **Codex CLI**, **Gemini CLI**, **Copilot**, **Cursor**, and any tool supporting the [Agent Skills](https://agentskills.io) standard.

## What it does

- **Detects tech stacks** automatically (Angular, React, Spring Boot, Flutter, Go, Rust, .NET, Python, and more)
- **Generates workspace files**: `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, coordinator and specialist agents
- **Creates repo symlinks** for direct filesystem access
- **Syncs managed blocks** in each repo's instruction files
- **Cross-platform**: bash (macOS/Linux/WSL) + PowerShell (Windows)

## Install

```bash
npx skills add <owner>/multirepo-space -g
```

## Usage

```bash
# Scaffold a new workspace
multirepo-space setup ~/my-workspace ~/repos/frontend ~/repos/backend ~/repos/shared

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

## How it works

`multirepo-space setup` creates a central workspace directory with:

```
my-workspace/
├── AGENTS.md                    # Universal instructions (Codex, Copilot, Gemini, etc.)
├── CLAUDE.md                    # Claude Code instructions (same content)
├── .claude/
│   ├── settings.json            # additionalDirectories for Claude Code
│   └── agents/
│       ├── coordinator.md       # Orchestrator agent
│       └── repo-<alias>.md      # Specialist per repo
├── .agents/
│   ├── coordinator.md           # Orchestrator agent (Codex compatible)
│   └── repo-<alias>.md          # Specialist per repo
├── repos/
│   ├── frontend -> /path/to/frontend
│   └── backend -> /path/to/backend
├── docs/
└── scripts/
```

Each external repo gets a managed block appended to its `AGENTS.md` and `CLAUDE.md` with workspace context.

## Agent Skill

This project is also an [Agent Skill](https://agentskills.io). When installed, AI agents can invoke it automatically when you say things like "create a multi-repo workspace" or "add a repo to the workspace".

The SKILL.md is intentionally minimal (~25 lines) — all heavy lifting is done by the bundled scripts, consuming zero tokens.

## Compatibility

| Tool | Reads | Generated files |
|------|-------|-----------------|
| Claude Code | `~/.claude/skills/` | `.claude/settings.json`, `CLAUDE.md`, `.claude/agents/` |
| Codex CLI | `~/.codex/skills/` | `AGENTS.md`, `.agents/` |
| Gemini CLI | `~/.gemini/skills/` | `AGENTS.md`, `.agents/` |
| Copilot | `.github/skills/` | `AGENTS.md` |
| Cursor | `~/.cursor/skills/` | `AGENTS.md` |

## License

MIT
