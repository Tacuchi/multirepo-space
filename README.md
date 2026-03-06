# multirepo-space

Multi-repo workspace manager for AI coding agents - an [Agent Skill](https://agentskills.io) that orchestrates [`@tacuchi/agent-factory`](https://www.npmjs.com/package/@tacuchi/agent-factory) and a bundled workspace setup script.

Compatibility priority:

1. `P0` Claude Code + Codex
2. `P1` Gemini + OpenCode (legacy) + Crush
3. `P2` Warp Oz via Agent Skills portability

## Architecture

This SKILL orchestrates two tools:

- **`@tacuchi/agent-factory`** - npm CLI that detects tech stacks and creates AI agents in multi-target output profiles
- **`workspace-setup.sh`** - bundled bash script for workspace infrastructure (dirs, symlinks, settings.json, docs)

```text
multirepo-space (SKILL)
├── SKILL.md
├── scripts/
│   └── workspace-setup.sh
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

1. **Detect stacks** - `agent-factory detect <path> --json -q` for each repo
2. **Create infrastructure** - `workspace-setup.sh setup` creates dirs, symlinks, settings.json, AGENTS.md/CLAUDE.md
3. **Create agents** - `agent-factory create --target all` generates specialist + coordinator agents and multi-CLI artifacts

### Generated workspace (target: `all`)

```text
my-workspace/
├── AGENTS.md
├── CLAUDE.md
├── .claude/
│   ├── settings.json
│   ├── .multirepo-space.conf
│   └── agents/
│       ├── coordinator-agent.md
│       └── repo-<alias>-agent.md
├── .agents/
│   ├── coordinator-agent.md
│   ├── repo-<alias>-agent.md
│   └── skills/
│       ├── coordinator-agent/SKILL.md
│       └── repo-<alias>-agent/SKILL.md
├── .gemini/
│   └── agents/
│       ├── coordinator-agent.md
│       └── repo-<alias>-agent.md
├── .opencode.json
├── .crush.json
├── docs/
│   └── warp-oz/
│       └── environment-example.md
├── repos/
│   ├── frontend -> /path/to/frontend
│   └── backend -> /path/to/backend
└── scripts/
```

### Agent hierarchy

```text
Coordinator (opus)
├── repo-frontend-agent (sonnet)
├── repo-backend-agent (sonnet)
└── repo-shared-agent (sonnet)
```

Custom agents (architecture, style, code-review) can be added via `agent-factory create --role custom --target all`.

## Multi-agent compatibility

- `.claude/agents/*.md` - Claude Code
- `.agents/*.md` - Codex and universal markdown agents
- `.agents/skills/<name>/SKILL.md` - Warp, Codex, Cursor, Gemini (skills portability)
- `.gemini/agents/*.md` - Gemini local agent definitions
- `.opencode.json` - OpenCode legacy bridge config
- `.crush.json` - Crush config bridge
- `docs/warp-oz/environment-example.md` - Warp Oz reference scaffold
- `AGENTS.md` - shared project rules for 20+ tools

## Local smoke check

To validate end-to-end generation:

```bash
bash scripts/smoke-multi-cli.sh
```

## Prerequisites

- Node.js 16+ (for npx)
- bash (macOS/Linux/WSL)

## License

MIT
