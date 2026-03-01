---
name: multirepo-space
description: |
  Scaffold and manage multi-repo workspaces for AI coding agents.
  Orchestrates workspace-setup.sh (infrastructure) and agent-factory CLI (agents).
  Use when user says "create workspace", "setup multirepo", "multi-repo workspace",
  "add repo to workspace", "remove repo from workspace",
  "workspace status", "check workspace health", "init multi-repo",
  "orchestrate repos", "link repositories".
  Also use when user has multiple repos and needs a central
  coordination point for AI agents (Claude Code, Codex, Gemini CLI).
---

# multirepo-space

## Tools

This SKILL orchestrates two tools:
- `workspace-setup.sh` — bundled script for workspace infrastructure (dirs, symlinks, settings.json, AGENTS.md/CLAUDE.md)
- `agent-factory` — npm CLI for creating AI agents (`npx @tacuchi/agent-factory`)

## Quick routing

User intent → Action:
- "Create/scaffold workspace" → **Full setup flow**
- "Add a repo" → **Add flow**
- "Remove/detach repo" → **Remove flow**
- "Check/verify/health" → **Status flow**
- "Create an agent" → `agent-factory create` directly
- Single repo project → DO NOT use this Skill
- Monorepo (Nx/Turborepo) → DO NOT use this Skill

## Before running — decision guide

Ask the user before executing:
1. Does the workspace directory already exist? If not, create it first (`mkdir`).
2. Is this a NEW workspace or adding to an EXISTING one? → full setup vs add.
3. Are all repo paths absolute? They MUST be absolute — symlinks break with relative paths.
4. First time? Always suggest `--dry-run` so user can preview changes.

## Full setup flow

Execute these steps in order:

### Step 1: Detect stacks
For each repo, run:
```
npx @tacuchi/agent-factory detect <repo_path> --json -q
```
Capture the JSON output. Extract `alias`, `primaryTech`, `stackCsv`, `verifyCommands`.

**Important**: Use the `stackCsv` field exactly as returned by detect — do NOT simplify or summarize it. Pass the full value to `--stacks`.

### Step 2: Create workspace infrastructure
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" setup <workspace_path> <repo1> <repo2> ... \
  --stacks "stackCsv1|stackCsv2|..." -y
```
This creates: dirs (repos/, docs/, scripts/), symlinks, .claude/settings.json, AGENTS.md, CLAUDE.md, config.

### Step 3: Create specialist agents
For each repo:
```
npx @tacuchi/agent-factory create \
  --name repo-<alias> \
  --role specialist \
  --scope <repo_path> \
  --output <workspace_path> \
  --target all -y -q
```
agent-factory auto-appends `-agent` suffix: `repo-<alias>` becomes `repo-<alias>-agent.md`.

### Step 4: Create coordinator agent
```
npx @tacuchi/agent-factory create \
  --name coordinator \
  --role coordinator \
  --model opus \
  --specialists "repo-<alias1>-agent,repo-<alias2>-agent,..." \
  --repo-count <N> \
  --output <workspace_path> \
  --target all -y -q
```
The `--specialists` list must use the full names with `-agent` suffix.

## Add repo flow

### Step 1: Detect stack
```
npx @tacuchi/agent-factory detect <repo_path> --json -q
```

### Step 2: Add to workspace
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" add <workspace_path> <repo_path> \
  --alias <alias> --stack-csv "<stackCsv>" -y
```

### Step 3: Create specialist
```
npx @tacuchi/agent-factory create \
  --name repo-<alias> \
  --role specialist \
  --scope <repo_path> \
  --output <workspace_path> \
  --target all -y -q
```

### Step 4: Regenerate coordinator
Get the updated list of specialists (with `-agent` suffix) from existing symlinks, then:
```
npx @tacuchi/agent-factory create \
  --name coordinator \
  --role coordinator \
  --model opus \
  --specialists "<updated_csv_list_with_agent_suffix>" \
  --repo-count <updated_N> \
  --output <workspace_path> \
  --target all -y -q
```

## Remove repo flow

### Step 1: Remove infrastructure + agent files
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" remove <workspace_path> <alias> -y
```
This removes: symlink, agent files from 3 dirs (.agents/, .claude/agents/, .agents/skills/), and regenerates docs.

### Step 2: Regenerate coordinator
Get the updated list of specialists from remaining symlinks, then:
```
npx @tacuchi/agent-factory create \
  --name coordinator \
  --role coordinator \
  --model opus \
  --specialists "<updated_csv_list>" \
  --repo-count <updated_N> \
  --output <workspace_path> \
  --target all -y -q
```

## Status flow

```
bash "$SKILL_DIR/scripts/workspace-setup.sh" status <workspace_path>
npx @tacuchi/agent-factory list <workspace_path>
```

## Custom agent flow

To create additional agents (architecture, style, code-review, etc.):
```
npx @tacuchi/agent-factory create \
  --name <agent-name> \
  --role custom \
  --description "<short description>" \
  --instructions "<body text or path to .md file>" \
  --model sonnet \
  --output <workspace_path> \
  --target all -y -q
```

## If detect returns "Generic"

Ask the user: "Stack was not auto-detected for [repo]. What is the main language/framework?"
Then pass `--stack-csv` to the setup/add command so it persists in config.

## When NOT to use this

- Single repo projects — no benefit, just overhead.
- True monorepos (one repo, multiple packages) — use monorepo tools (Nx, Turborepo) instead.

## NEVER

- Run setup on a populated workspace without confirming with the user first.
- Use relative paths for repos — symlinks will break.
- Skip `--dry-run` for first-time users.
- Assume workspace exists — verify with `status` before running `add` or `remove`.
- Modify `settings.json` manually — the script expects a specific format.

## Prerequisites

- Node.js 16+ (for npx)
- `@tacuchi/agent-factory` (installed globally or via npx)
- bash (macOS/Linux/WSL)

Replace `$SKILL_DIR` with the absolute path to this skill's directory.

## Script behavior summary

`workspace-setup.sh` is fully offline — makes NO network requests, does NOT modify system files.
Scope of writes is limited to the workspace directory.

## Agent hierarchy

```
coordinator-agent (opus)
├── repo-frontend-agent (sonnet)
├── repo-backend-agent (sonnet)
└── repo-shared-agent (sonnet)
```

The coordinator acts as a contextual guide — it orients the user on which specialist to invoke but does not automatically delegate tasks. Each specialist is invoked directly by the user.

## Multi-agent compatibility

- `.claude/agents/*.md` → YAML frontmatter (name, model, description, tools) for Claude Code
- `.agents/*.md` → plain markdown (Codex/Gemini/Cursor compatible)
- `.agents/skills/<name>/SKILL.md` → Agent Skills standard (Warp/Codex/Cursor/Gemini CLI)
- `AGENTS.md` is used as project rules by Warp, Codex, Gemini CLI, Cursor and 20+ tools

## After running

- Run `status` to verify symlinks and agent parity.
- To start working: `cd <workspace_path> && claude` or `cd <workspace_path> && codex`.
