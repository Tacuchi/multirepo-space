# multirepo-space

Multi-repo workspace manager for AI coding agents — an [Agent Skill](https://agentskills.io) that orchestrates [`@tacuchi/agent-factory`](https://www.npmjs.com/package/@tacuchi/agent-factory) and a bundled workspace setup script.

Compatible with **Claude Code**, **Codex CLI**, **Gemini CLI**, **Copilot**, **Cursor**, and any tool supporting the Agent Skills standard.

## Architecture

This SKILL orchestrates two tools:

- **`@tacuchi/agent-factory`** — npm CLI that detects tech stacks and creates AI agents in 3 formats
- **`workspace-setup.sh`** — bundled bash script for workspace infrastructure (dirs, symlinks, settings.json, docs)

```
multirepo-space (SKILL)
├── SKILL.md              # Teaches the AI agent when/how to use both tools
├── scripts/
│   └── workspace-setup.sh  # Infrastructure: dirs, symlinks, settings.json, AGENTS.md
├── templates/
│   ├── workspace-instructions.md.tmpl
│   └── settings.json.tmpl
├── README.md
└── LICENSE
```

## Install

```bash
npx skills add <owner>/multirepo-space -g
```

## How it works

When you tell your AI agent "create a multi-repo workspace", the SKILL orchestrates:

1. **Detect stacks** — `agent-factory detect <path> --json -q` for each repo
2. **Create infrastructure** — `workspace-setup.sh setup` creates dirs, symlinks, settings.json, AGENTS.md/CLAUDE.md
3. **Create agents** — `agent-factory create` generates specialist + coordinator agents in 3 formats

### Generated workspace

```
my-workspace/
├── AGENTS.md                    # Universal instructions
├── CLAUDE.md                    # Claude Code instructions
├── .claude/
│   ├── settings.json            # additionalDirectories
│   ├── .multirepo-space.conf    # Persisted config (stacks, paths)
│   └── agents/
│       ├── coordinator.md       # With YAML frontmatter
│       └── repo-<alias>.md      # Specialist per repo
├── .agents/
│   ├── coordinator.md           # Plain markdown (Codex/Gemini)
│   ├── repo-<alias>.md
│   └── skills/
│       ├── coordinator/SKILL.md # Agent Skills standard
│       └── repo-<alias>/SKILL.md
├── repos/
│   ├── frontend -> /path/to/frontend
│   └── backend -> /path/to/backend
├── docs/
└── scripts/
```

### Agent hierarchy

```
Coordinator (opus)
├── repo-frontend (sonnet)
├── repo-backend (sonnet)
└── repo-shared (sonnet)
```

Custom agents (architecture, style, code-review) can be added via `agent-factory create --role custom`.

## Multi-agent compatibility

- `.claude/agents/*.md` — YAML frontmatter for Claude Code
- `.agents/*.md` — plain markdown for Codex, Gemini, Cursor
- `.agents/skills/<name>/SKILL.md` — Agent Skills standard for Warp, Codex, Cursor, Gemini CLI
- `AGENTS.md` — project rules for 20+ tools

## Prerequisites

- Node.js 16+ (for npx)
- bash (macOS/Linux/WSL)

## License

MIT
